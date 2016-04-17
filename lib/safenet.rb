require "safenet/version"
require "net/http"
require "rbnacl"
require "base64"
require "json"
require "cgi" # CGI.escape method

# usage:
#  my_client = SafeNet::Client.new(name: 'My App')
#  my_client.nfs.file('x.txt')
#  my_client.nfs.update_file_content('x.txt', 'Hello World!')
#  my_client.nfs.get_file('x.txt')
module SafeNet

  class Client
    attr_reader :auth, :nfs, :dns, :sd, :app_info, :key_helper

    def initialize(options = {})
      @app_info = defaults()
      set_app_info(options) if options.any?
      @key_helper = SafeNet::KeyHelper.new(self)
      @auth = SafeNet::Auth.new(self)
      @nfs = SafeNet::NFS.new(self)
      @dns = SafeNet::DNS.new(self)
      @sd = SafeNet::SD.new(self)
    end

    def set_app_info(options = {})
      @app_info[:name] = options[:name] if options.has_key?(:name)
      @app_info[:version] = options[:version] if options.has_key?(:version)
      @app_info[:vendor] = options[:vendor] if options.has_key?(:vendor)
      @app_info[:id] = options[:id] if options.has_key?(:id)
      @app_info[:launcher_server] = options[:server] if options.has_key?(:server)
      @app_info[:conf_path] = options[:conf_file] if options.has_key?(:conf_file)
    end

    private

    # default values
    def defaults
      {
        name: "Ruby Demo App",
        version: "0.0.1",
        vendor: "Vendor's Name",
        id: "org.thevendor.demo",
        launcher_server: "http://localhost:8100/",
        conf_path: File.join(File.expand_path('..', __FILE__), "conf.json")
      }
    end
  end

  class KeyHelper

    def initialize(client_obj)
      @client = client_obj
      @keys = {}
      @conf = {}
    end

    def get_token
      @conf = File.exists?(@client.app_info[:conf_path]) ? JSON.parse(File.read(@client.app_info[:conf_path])) : (@client.auth.auth() || {})
      @conf["token"]
    end

    def get_valid_token
      @last_conf = File.exists?(@client.app_info[:conf_path]) ? JSON.parse(File.read(@client.app_info[:conf_path])) : {}
      @client.auth.auth() unless File.exists?(@client.app_info[:conf_path]) && @client.auth.is_token_valid()
      @conf = JSON.parse(File.read(@client.app_info[:conf_path]))
      @conf["token"]
    end

    def decrypt(message_base64)
      keys = get_keys()
      keys["secret_box"].decrypt(keys["symmetric_nonce"], Base64.strict_decode64(message_base64))
    end

    def encrypt(message)
      keys = get_keys()
      res = keys["secret_box"].encrypt(keys["symmetric_nonce"], message)
      Base64.strict_encode64(res)
    end

    def invalidate
      @keys = {}
    end

    private

    def get_keys
      # not loaded yet?
      if @keys.empty?
        get_valid_token() if @conf.empty?

        # extract keys
        cipher_text = Base64.strict_decode64(@conf["encryptedKey"])
        nonce = Base64.strict_decode64(@conf["nonce"])
        private_key = Base64.strict_decode64(@conf["privateKey"])
        public_key = Base64.strict_decode64(@conf["publicKey"])

        box = RbNaCl::Box.new(public_key, private_key)
        data = box.decrypt(nonce, cipher_text)

        # The first segment of the data will have the symmetric key
        @keys["symmetric_key"] = data.slice(0, RbNaCl::SecretBox.key_bytes)

        # The second segment of the data will have the nonce to be used
        @keys["symmetric_nonce"] = data.slice(RbNaCl::SecretBox.key_bytes, RbNaCl::SecretBox.key_bytes)

        # keep the box object in cache
        @keys["secret_box"] = RbNaCl::SecretBox.new(@keys["symmetric_key"])
      end

      @keys
    end

  end

  class Auth
    def initialize(client_obj)
      @client = client_obj
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
    # Usage: my_client.auth()
    # Fail: nil
    # Success: {token: "1222", encryptedKey: "232", "publicKey": "4323", "permissions": []}
    #
    # Reference: https://maidsafe.readme.io/docs/auth
    #
    def auth
      # entry point
      url = "#{@client.app_info[:launcher_server]}auth"

      # new random key
      private_key = RbNaCl::PrivateKey.generate
      nonce = RbNaCl::Random.random_bytes(24)

      # payload
      payload = {
        app: {
          name: @client.app_info[:name],
          version: @client.app_info[:version],
          vendor: @client.app_info[:vendor],
          id: @client.app_info[:id]
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
        File.open(@client.app_info[:conf_path], "w") { |f| f << JSON.pretty_generate(conf) }

        # invalidates @keys
        @client.key_helper.invalidate()
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
    def is_token_valid
      # entry point
      url = "#{@client.app_info[:launcher_server]}auth"

      # api call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Get.new(uri.path, {
        'Authorization' => "Bearer #{@client.key_helper.get_token()}"
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
    def revoke_token
      # entry point
      url = "#{@client.app_info[:launcher_server]}auth"

      # api call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Delete.new(uri.path, {
        'Authorization' => "Bearer #{@client.key_helper.get_valid_token()}"
      })
      res = http.request(req)
      res.code == "200"
    end
  end


  class NFS
    def initialize(client_obj)
      @client = client_obj
    end

    #
    # Create a directory using the NFS API.
    # Only authorised requests can create a directory.
    #
    # Usage: SafeNet.get_directory("/photos", is_path_shared: false)
    # Fail: {"errorCode"=>-1502, "description"=>"FfiError::PathNotFound"}
    # Success: {"info"=> {"name"=> "Ruby Demo App-Root-Dir", ...}, ...}
    #
    # Reference: https://maidsafe.readme.io/docs/nfs-get-directory
    #
    def get_directory(dir_path, options = {})
      # default values
      options[:is_path_shared] = false if ! options.has_key?(:is_path_shared)

      # entry point
      url = "#{@client.app_info[:launcher_server]}nfs/directory/#{CGI.escape(dir_path)}/#{options[:is_path_shared]}"

      # api call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Get.new(uri.path, {
        'Authorization' => "Bearer #{@client.key_helper.get_valid_token()}",
      })
      res = http.request(req)
      JSON.parse(@client.key_helper.decrypt(res.body))
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
    def file(file_path, options = {})
      url = "#{@client.app_info[:launcher_server]}nfs/file"

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
        'Authorization' => "Bearer #{@client.key_helper.get_valid_token()}",
        'Content-Type' => 'text/plain'
      })
      req.body = @client.key_helper.encrypt(payload.to_json)
      res = http.request(req)
      res.code == "200" ? true : JSON.parse(@client.key_helper.decrypt(res.body))
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
    def create_directory(dir_path, options = {})
      # entry point
      url = "#{@client.app_info[:launcher_server]}nfs/directory"

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
        'Authorization' => "Bearer #{@client.key_helper.get_valid_token()}",
        'Content-Type' => 'text/plain'
      })
      req.body = @client.key_helper.encrypt(payload.to_json)
      res = http.request(req)
      res.code == "200" ? true : JSON.parse(@client.key_helper.decrypt(res.body))
    end


    # ex.: delete_directory("/photos")
    def delete_directory(dir_path, options = {})
      # default values
      options[:is_path_shared] = false if ! options.has_key?(:is_path_shared)

      # entry point
      url = "#{@client.app_info[:launcher_server]}nfs/directory/#{CGI.escape(dir_path)}/#{options[:is_path_shared]}"

      # api call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Delete.new(uri.path, {
        'Authorization' => "Bearer #{@client.key_helper.get_valid_token()}",
      })
      res = http.request(req)
      res.code == "200" ? true : JSON.parse(@client.key_helper.decrypt(res.body))
    end

    # options: offset, length, is_path_shared
    def get_file(file_path, options = {})
      # default values
      options[:offset]         = 0     if ! options.has_key?(:offset)
      options[:is_path_shared] = false if ! options.has_key?(:is_path_shared)

      # entry point
      url = "#{@client.app_info[:launcher_server]}nfs/file/#{CGI.escape(file_path)}/#{options[:is_path_shared]}?"

      # query params are encrypted
      query = []
      query << "offset=#{options[:offset]}"
      query << "length=#{options[:length]}" if options.has_key?(:length) # length is optional
      url = "#{url}#{@client.key_helper.encrypt(query.join('&'))}"

      # api call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Get.new(uri.path, {
        'Authorization' => "Bearer #{@client.key_helper.get_valid_token()}",
      })
      res = http.request(req)
      res.code == "200" ? @client.key_helper.decrypt(res.body) : JSON.parse(@client.key_helper.decrypt(res.body))
    end

    def update_file_content(file_path, contents, options = {})
      # default values
      options[:offset]         = 0     if ! options.has_key?(:offset)
      options[:is_path_shared] = false if ! options.has_key?(:is_path_shared)

      # entry point
      url = "#{@client.app_info[:launcher_server]}nfs/file/#{CGI.escape(file_path)}/#{options[:is_path_shared]}?offset=#{options[:offset]}"

      # api call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Put.new(uri.path, {
        'Authorization' => "Bearer #{@client.key_helper.get_valid_token()}",
        'Content-Type' => 'text/plain'
      })
      req.body = @client.key_helper.encrypt(contents)
      res = http.request(req)
      res.code == "200" ? true : JSON.parse(@client.key_helper.decrypt(res.body))
    end

    def delete_file(file_path, options = {})
      # default values
      options[:is_path_shared] = false if ! options.has_key?(:is_path_shared)

      # entry point
      url = "#{@client.app_info[:launcher_server]}nfs/file/#{CGI.escape(file_path)}/#{options[:is_path_shared]}"

      # api call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Delete.new(uri.path, {
        'Authorization' => "Bearer #{@client.key_helper.get_valid_token()}",
      })
      res = http.request(req)
      res.code == "200" ? true : JSON.parse(@client.key_helper.decrypt(res.body))
    end
  end


  class DNS
    def initialize(client_obj)
      @client = client_obj
    end

    # https://maidsafe.readme.io/docs/dns-create-long-name
    def create_long_name(long_name)
      # entry point
      url = "#{@client.app_info[:launcher_server]}dns/#{CGI.escape(long_name)}"

      # api call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Post.new(uri.path, {
        'Authorization' => "Bearer #{@client.key_helper.get_valid_token()}",
        'Content-Type' => 'text/plain'
      })
      res = http.request(req)
      res.code == "200" ? true : JSON.parse(@client.key_helper.decrypt(res.body))
    end


    # ex.: register_service("thegoogle", "www", "/www")
    # https://maidsafe.readme.io/docs/dns-register-service
    def register_service(long_name, service_name, service_home_dir_path, options = {})
      # entry point
      url = "#{@client.app_info[:launcher_server]}dns"

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
        'Authorization' => "Bearer #{@client.key_helper.get_valid_token()}",
        'Content-Type' => 'text/plain'
      })
      req.body = @client.key_helper.encrypt(payload.to_json)
      res = http.request(req)
      res.code == "200" ? true : JSON.parse(@client.key_helper.decrypt(res.body))
    end

    # https://maidsafe.readme.io/docs/dns-list-long-names
    def list_long_names
      # entry point
      url = "#{@client.app_info[:launcher_server]}dns"

      # api call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Get.new(uri.path, {
        'Authorization' => "Bearer #{@client.key_helper.get_valid_token()}",
      })
      res = http.request(req)
      JSON.parse(@client.key_helper.decrypt(res.body))
    end

    # https://maidsafe.readme.io/docs/dns-list-services
    def list_services(long_name)
      # entry point
      url = "#{@client.app_info[:launcher_server]}dns/#{CGI.escape(long_name)}"

      # api call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Get.new(uri.path, {
        'Authorization' => "Bearer #{@client.key_helper.get_valid_token()}",
      })
      res = http.request(req)
      JSON.parse(@client.key_helper.decrypt(res.body))
    end


    # https://maidsafe.readme.io/docs/dns-get-home-dir
    def get_home_dir(long_name, service_name)
      # entry point
      url = "#{@client.app_info[:launcher_server]}dns/#{CGI.escape(service_name)}/#{CGI.escape(long_name)}"

      # api call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Get.new(uri.path)
      res = http.request(req)
      JSON.parse(res.body)
    end


    # https://maidsafe.readme.io/docs/dns-get-file-unauth
    # get_file_unauth("thegoogle", "www", "index.html", offset: 3, length: 5)
    def get_file_unauth(long_name, service_name, file_path, options = {})
      # default values
      options[:offset] = 0 if ! options.has_key?(:offset)

      # entry point
      url = "#{@client.app_info[:launcher_server]}dns/#{CGI.escape(service_name)}/#{CGI.escape(long_name)}/#{CGI.escape(file_path)}?"

      # query params are encrypted
      query = []
      query << "offset=#{options[:offset]}"
      query << "length=#{options[:length]}" if options.has_key?(:length) # length is optional
      url = "#{url}#{@client.key_helper.encrypt(query.join('&'))}"

      # api call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Get.new(uri.path)
      res = http.request(req)
      res.code == "200" ? res.body : JSON.parse(res.body)
    end
  end

  class SD
    def initialize(client_obj)
      @client = client_obj
    end

    def create(id, tag_type, contents)
      version = 1
      new_id = Digest::SHA2.new(512).hexdigest("#{id}#{tag_type}")
      res = @client.nfs.create_directory("/#{new_id}", is_private: false) == true
      res &&= @client.nfs.file("/#{new_id}/data.#{version}", is_private: false) == true
      res &&= @client.nfs.update_file_content("/#{new_id}/data.#{version}", contents) == true
      res &&= @client.dns.register_service("#{new_id}", "sd", "/#{new_id}") == true
      res
    end

    def update(id, tag_type, contents)
      version = 1
      new_id = Digest::SHA2.new(512).hexdigest("#{id}#{tag_type}")
      res = @client.nfs.update_file_content("/#{new_id}/data.#{version}", contents) == true
      res
    end

    def get(id, tag_type)
      version = 1
      new_id = Digest::SHA2.new(512).hexdigest("#{id}#{tag_type}")
      @client.dns.get_file_unauth("#{new_id}", "sd", "data.#{version}")
    end
  end
end
