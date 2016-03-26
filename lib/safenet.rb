require "safenet/version"

module SafeNet
  require "net/http"
  require "rbnacl"
  require "base64"
  require "json"
  require "cgi" # CGI.escape method

  # default values
  @@NAME = "Ruby Demo App"
  @@VERSION = "0.0.1"
  @@VENDOR = "Vendor's Name"
  @@ID = "org.thevendor.demo"
  @@LAUNCHER_SERVER = "http://localhost:8100/"
  @@CONF_PATH = File.join(File.expand_path('..', __FILE__), "conf.json")

  def self.set_app_info(options)
    @@NAME = options[:name] if options.has_key?(:name)
    @@VERSION = options[:version] if options.has_key?(:version)
    @@VENDOR = options[:vendor] if options.has_key?(:vendor)
    @@ID = options[:id] if options.has_key?(:id)
    @@LAUNCHER_SERVER = options[:server] if options.has_key?(:server)
    @@CONF_PATH = options[:conf_file] if options.has_key?(:conf_file)
  end

  #
  # An application exchanges data with the SAFE Launcher using symmetric key
  #   encryption. The symmetric key is session based and is securely transferred
  #   from the SAFE Launcher to the application using ECDH Key Exchange.
  # Applications will generate an asymmetric key pair and a nonce for ECDH Key
  #   Exchange with the SAFE Launcher.
  #
  # The application will initiate the authorisation request with the generated
  #   nonce and public key, along with information about the application and the
  #   required permissions.
  #
  # The SAFE Launcher will prompt to the user with the application information
  #   along with the requested permissions. Once the user authorises the
  #   request, the symmetric keys for encryption are received. If the user
  #   denies the request then the SAFE Launcher sends an unauthorised error
  #   response.
  #
  # Usage: SafeNet.auth()
  # Fail: nil
  # Success: {token: "1222", encryptedKey: "232", "publicKey": "4323", "permissions": []}
  #
  # Reference: https://maidsafe.readme.io/docs/auth
  #
  def self.auth
    # entry point
    url = "#{@@LAUNCHER_SERVER}auth"

    # new random key
    private_key = RbNaCl::PrivateKey.generate
    nonce = RbNaCl::Random.random_bytes(24)

    # payload
    payload = {
      app: {
        name: @@NAME,
        version: @@VERSION,
        vendor: @@VENDOR,
        id: @@ID
      },
      publicKey: Base64.strict_encode64(private_key.public_key),
      nonce: Base64.strict_encode64(nonce),
      permissions: []
    }

    # api call
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    req = Net::HTTP::Post.new(uri.path, {'Content-Type' => 'application/json'})
    req.body = payload.to_json
    res = http.request(req)

    # return's parser
    if res.code == "200"
      response = JSON.parse(res.body)

      # save it in conf.json
      conf = response.dup
      conf["nonce"] = Base64.strict_encode64(nonce)
      conf["privateKey"] = Base64.strict_encode64(private_key)
      File.open(@@CONF_PATH, "w") { |f| f << JSON.pretty_generate(conf) }

      # invalidates @@keys
      @@keys = {}
    else
      # puts "ERROR #{res.code}: #{res.message}"
      response = nil
    end

    # return
    response
  end


  #
  # To check whether the authorisation token obtained is valid.
  # The Authorization header must be present in the request.
  #
  # Usage: SafeNet.is_token_valid()
  # Fail: false
  # Success: true
  #
  # Reference: https://maidsafe.readme.io/docs/is-token-valid
  #
  def self.is_token_valid
    # entry point
    url = "#{@@LAUNCHER_SERVER}auth"

    # api call
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    req = Net::HTTP::Get.new(uri.path, {
      'Authorization' => "Bearer #{self.get_token()}"
    })
    res = http.request(req)
    res.code == "200"
  end


  #
  # Removes the token from the SAFE Launcher.
  #
  # Usage: SafeNet.revoke_token()
  # Fail: false
  # Success: true
  #
  # Reference: https://maidsafe.readme.io/docs/revoke-token
  #
  def self.revoke_token
    # entry point
    url = "#{@@LAUNCHER_SERVER}auth"

    # api call
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    req = Net::HTTP::Delete.new(uri.path, {
      'Authorization' => "Bearer #{self.get_valid_token()}"
    })
    res = http.request(req)
    res.code == "200"
  end


  #
  # Create a directory using the NFS API.
  # Only authorised requests can create a directory.
  #
  # Usage: SafeNet.get_directory("/photos", is_path_shared: false)
  # Fail: {"errorCode"=>-1502, "description"=>"FfiError::PathNotFound"}
  # Success: {"info"=> {"name"=> "Ruby Demo App-Root-Dir", ...}, ...}
  #
  # Reference: https://maidsafe.readme.io/docs/nfs-create-directory
  #
  def self.get_directory(dir_path, options = {})
    # default values
    options[:is_path_shared] = false if ! options.has_key?(:is_path_shared)

    # entry point
    url = "#{@@LAUNCHER_SERVER}nfs/directory/#{CGI.escape(dir_path)}/#{options[:is_path_shared]}"

    # api call
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    req = Net::HTTP::Get.new(uri.path, {
      'Authorization' => "Bearer #{self.get_valid_token()}",
    })
    res = http.request(req)
    JSON.parse(self.decrypt(res.body))
  end


  #
  # Create a File using the NFS API.
  # Only authorised requests can invoke the API.
  #
  # Usage: SafeNet.file("/photos/cat.jpg")
  # Adv.Usage: SafeNet.file("/photos/cat.jpg", is_private: true, metadata: "some meta", is_path_shared: false, is_versioned: false)
  # Fail: {"errorCode"=>-505, "description"=>"NfsError::FileAlreadyExistsWithSameName"}
  # Success: true
  #
  # Reference: https://maidsafe.readme.io/docs/nfsfile
  #
  def self.file(file_path, options = {})
    url = "#{@@LAUNCHER_SERVER}nfs/file"

    # default values
    options[:is_private]     = true  if ! options.has_key?(:is_private)
    options[:is_versioned]   = false if ! options.has_key?(:is_versioned)
    options[:is_path_shared] = false if ! options.has_key?(:is_path_shared)

    # payload
    payload = {
      filePath: file_path,
      isPrivate: options[:is_private],
      isVersioned: options[:is_versioned],
      isPathShared: options[:is_path_shared]
    }

    # optional
    payload["metadata"] = Base64.strict_encode64(options[:metadata]) if options.has_key?(:metadata)

    # api call
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    req = Net::HTTP::Post.new(uri.path, {
      'Authorization' => "Bearer #{self.get_valid_token()}",
      'Content-Type' => 'text/plain'
    })
    req.body = self.encrypt(payload.to_json)
    res = http.request(req)
    res.code == "200" ? true : JSON.parse(self.decrypt(res.body))
  end


  #
  # Create a directory using the NFS API.
  # Only authorised requests can create a directory.
  #
  # Usage: SafeNet.create_directory("/photos")
  # Adv.Usage: SafeNet.create_directory("/photos", is_private: true, metadata: "some meta", is_path_shared: false, is_versioned: false)
  # Fail: {"errorCode"=>-505, "description"=>"NfsError::FileAlreadyExistsWithSameName"}
  # Success: true
  #
  # Reference: https://maidsafe.readme.io/docs/nfs-create-directory
  #
  def self.create_directory(dir_path, options = {})
    # entry point
    url = "#{@@LAUNCHER_SERVER}nfs/directory"

    # default values
    options[:is_private]     = true  if ! options.has_key?(:is_private)
    options[:is_versioned]   = false if ! options.has_key?(:is_versioned)
    options[:is_path_shared] = false if ! options.has_key?(:is_path_shared)

    # payload
    payload = {
      dirPath: dir_path,
      isPrivate: options[:is_private],
      isVersioned: options[:is_versioned],
      isPathShared: options[:is_path_shared]
    }

    # optional
    payload["metadata"] = Base64.strict_encode64(options[:metadata]) if options.has_key?(:metadata)

    # api call
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    req = Net::HTTP::Post.new(uri.path, {
      'Authorization' => "Bearer #{self.get_valid_token()}",
      'Content-Type' => 'text/plain'
    })
    req.body = self.encrypt(payload.to_json)
    res = http.request(req)
    res.code == "200" ? true : JSON.parse(self.decrypt(res.body))
  end


  # ex.: delete_directory("/photos")
  def self.delete_directory(dir_path, options = {})
    # default values
    options[:is_path_shared] = false if ! options.has_key?(:is_path_shared)

    # entry point
    url = "#{@@LAUNCHER_SERVER}nfs/directory/#{CGI.escape(dir_path)}/#{options[:is_path_shared]}"

    # api call
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    req = Net::HTTP::Delete.new(uri.path, {
      'Authorization' => "Bearer #{self.get_valid_token()}",
    })
    res = http.request(req)
    res.code == "200" ? true : JSON.parse(self.decrypt(res.body))
  end

  # options: offset, length, is_path_shared
  def self.get_file(file_path, options = {})
    # default values
    options[:offset]         = 0     if ! options.has_key?(:offset)
    options[:is_path_shared] = false if ! options.has_key?(:is_path_shared)

    # entry point
    url = "#{@@LAUNCHER_SERVER}nfs/file/#{CGI.escape(file_path)}/#{options[:is_path_shared]}?"

    # query params are encrypted
    query = []
    query << "offset=#{options[:offset]}"
    query << "length=#{options[:length]}" if options.has_key?(:length) # length is optional
    url = "#{url}#{self.encrypt(query.join('&'))}"

    # api call
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    req = Net::HTTP::Get.new(uri.path, {
      'Authorization' => "Bearer #{self.get_valid_token()}",
    })
    res = http.request(req)
    res.code == "200" ? self.decrypt(res.body) : JSON.parse(self.decrypt(res.body))
  end

  def self.update_file_content(file_path, contents, options = {})
    # default values
    options[:offset]         = 0     if ! options.has_key?(:offset)
    options[:is_path_shared] = false if ! options.has_key?(:is_path_shared)

    # entry point
    url = "#{@@LAUNCHER_SERVER}nfs/file/#{CGI.escape(file_path)}/#{options[:is_path_shared]}?offset=#{options[:offset]}"

    # api call
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    req = Net::HTTP::Put.new(uri.path, {
      'Authorization' => "Bearer #{self.get_valid_token()}",
      'Content-Type' => 'text/plain'
    })
    req.body = self.encrypt(contents)
    res = http.request(req)
    res.code == "200" ? true : JSON.parse(self.decrypt(res.body))
  end

  def self.delete_file(file_path, options = {})
    # default values
    options[:is_path_shared] = false if ! options.has_key?(:is_path_shared)

    # entry point
    url = "#{@@LAUNCHER_SERVER}nfs/file/#{CGI.escape(file_path)}/#{options[:is_path_shared]}"

    # api call
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    req = Net::HTTP::Delete.new(uri.path, {
      'Authorization' => "Bearer #{self.get_valid_token()}",
    })
    res = http.request(req)
    res.code == "200" ? true : JSON.parse(self.decrypt(res.body))
  end


  def self.create_long_name(long_name)
    # entry point
    url = "#{@@LAUNCHER_SERVER}dns/#{CGI.escape(long_name)}"

    # api call
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    req = Net::HTTP::Post.new(uri.path, {
      'Authorization' => "Bearer #{self.get_valid_token()}",
      'Content-Type' => 'text/plain'
    })
    res = http.request(req)
    res.code == "200" ? true : JSON.parse(self.decrypt(res.body))
  end


  # ex.: register_service("thegoogle", "www", "/www")
  def self.register_service(long_name, service_name, service_home_dir_path, options = {})
    # entry point
    url = "#{@@LAUNCHER_SERVER}dns"

    # default values
    options[:is_path_shared] = false if ! options.has_key?(:is_path_shared)

    # payload
    payload = {
      longName: long_name,
      serviceName: service_name,
      serviceHomeDirPath: service_home_dir_path,
      isPathShared: options[:is_path_shared]
    }

    # optional
    payload["metadata"] = options[:metadata] if options.has_key?(:metadata)

    # api call
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    req = Net::HTTP::Post.new(uri.path, {
      'Authorization' => "Bearer #{self.get_valid_token()}",
      'Content-Type' => 'text/plain'
    })
    req.body = self.encrypt(payload.to_json)
    res = http.request(req)
    res.code == "200" ? true : JSON.parse(self.decrypt(res.body))
  end


  def self.list_long_names
    # entry point
    url = "#{@@LAUNCHER_SERVER}dns"

    # api call
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    req = Net::HTTP::Get.new(uri.path, {
      'Authorization' => "Bearer #{self.get_valid_token()}",
    })
    res = http.request(req)
    JSON.parse(self.decrypt(res.body))
  end


  def self.list_services(long_name)
    # entry point
    url = "#{@@LAUNCHER_SERVER}dns/#{CGI.escape(long_name)}"

    # api call
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    req = Net::HTTP::Get.new(uri.path, {
      'Authorization' => "Bearer #{self.get_valid_token()}",
    })
    res = http.request(req)
    JSON.parse(self.decrypt(res.body))
  end


  def self.get_home_dir(long_name, service_name)
    # entry point
    url = "#{@@LAUNCHER_SERVER}dns/#{CGI.escape(service_name)}/#{CGI.escape(long_name)}"

    # api call
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    req = Net::HTTP::Get.new(uri.path)
    res = http.request(req)
    JSON.parse(res.body)
  end


  # get_file_unauth("thegoogle", "www", "index.html", offset: 3, length: 5)
  def self.get_file_unauth(long_name, service_name, file_path, options = {})
    # default values
    options[:offset] = 0 if ! options.has_key?(:offset)

    # entry point
    url = "#{@@LAUNCHER_SERVER}dns/#{CGI.escape(service_name)}/#{CGI.escape(long_name)}/#{CGI.escape(file_path)}?"

    # query params are encrypted
    query = []
    query << "offset=#{options[:offset]}"
    query << "length=#{options[:length]}" if options.has_key?(:length) # length is optional
    url = "#{url}#{self.encrypt(query.join('&'))}"

    # api call
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    req = Net::HTTP::Get.new(uri.path)
    res = http.request(req)
    res.code == "200" ? res.body : JSON.parse(res.body)
  end

  private

  def self.get_token
    @@conf = File.exists?(@@CONF_PATH) ? JSON.parse(File.read(@@CONF_PATH)) : (self.auth() || {})
    @@conf["token"]
  end

  def self.get_valid_token
    @last_conf = File.exists?(@@CONF_PATH) ? JSON.parse(File.read(@@CONF_PATH)) : {}
    self.auth() unless File.exists?(@@CONF_PATH) && self.is_token_valid()
    @@conf = JSON.parse(File.read(@@CONF_PATH))
    @@conf["token"]
  end


  def self.get_keys
    @@keys ||= {}

    # not loaded yet?
    if @@keys.empty?
      @@conf ||= {}
      self.get_valid_token if @@conf.empty?

      # extract keys
      cipher_text = Base64.strict_decode64(@@conf["encryptedKey"])
      nonce = Base64.strict_decode64(@@conf["nonce"])
      private_key = Base64.strict_decode64(@@conf["privateKey"])
      public_key = Base64.strict_decode64(@@conf["publicKey"])

      box = RbNaCl::Box.new(public_key, private_key)
      data = box.decrypt(nonce, cipher_text)

      # The first segment of the data will have the symmetric key
      @@keys["symmetric_key"] = data.slice(0, RbNaCl::SecretBox.key_bytes)

      # The second segment of the data will have the nonce to be used
      @@keys["symmetric_nonce"] = data.slice(RbNaCl::SecretBox.key_bytes, RbNaCl::SecretBox.key_bytes)

      # keep the box object in cache
      @@keys["secret_box"] = RbNaCl::SecretBox.new(@@keys["symmetric_key"])
    end

    @@keys
  end

  def self.decrypt(message_base64)
    keys = self.get_keys
    keys["secret_box"].decrypt(keys["symmetric_nonce"], Base64.strict_decode64(message_base64))
  end

  def self.encrypt(message)
    keys = self.get_keys
    res = keys["secret_box"].encrypt(keys["symmetric_nonce"], message)
    Base64.strict_encode64(res)
  end

end
