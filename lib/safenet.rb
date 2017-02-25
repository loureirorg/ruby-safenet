require "safenet/version"
require "net/http"
require "base64"
require "json"
require "cgi" # CGI.escape method

API_VERSION = 0.5
API_ENDPOINT = "http://localhost:8100/"

module SafeNet

  class Client
    attr_reader :auth, :nfs, :dns, :sd, :ad, :immutable, :cipher, :data_id, :app_info, :key_helper

    def initialize(options = {})
      @app_info = defaults()
      set_app_info(options) if options.any?
      @key_helper = SafeNet::KeyHelper.new(self)
      @auth = SafeNet::Auth.new(self)
      @nfs = SafeNet::NFS.new(self)
      @dns = SafeNet::DNS.new(self)
      @sd = SafeNet::SD.new(self)
      @ad = SafeNet::AD.new(self)
      @immutable = SafeNet::Immutable.new(self)
      @cipher = SafeNet::Cipher.new(self)
      @data_id = SafeNet::DataId.new(self)
    end

    def set_app_info(options = {})
      @app_info[:permissions] = options[:permissions] if options.has_key?(:permissions)
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
        launcher_server: API_ENDPOINT,
        conf_path: File.join(File.expand_path('..', __FILE__), "conf.json")
      }
    end
  end

  class KeyHelper

    def initialize(client_obj)
      @client = client_obj
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

  end

  class Auth
    def initialize(client_obj)
      @client = client_obj
    end

    #
    # Any application that wants to access API endpoints that require authorised
    #  access must receive an authorisation token from SAFE Launcher.
    #
    # Reading public data using the DNS API does not require an authorisation
    #  token. All other API endpoints require authorised access.
    #
    # The application will initiate the authorisation request with information
    #  about the application itself and the required permissions. SAFE Launcher
    #  will then display a prompt to the user with the application information
    #  along with the requested permissions. Once the user authorises the
    #  request, the application will receive an authorisation token. If the user
    #  denies the request, the application will receive an unauthorised error
    #  response.
    #
    # Usage: my_client.auth.auth(["SAFE_DRIVE_ACCESS"])
    # Fail: nil
    # Success: {token: "1222", "permissions": []}
    #
    # Reference: https://maidsafe.readme.io/docs/auth
    #
    def auth()
      # entry point
      url = "#{@client.app_info[:launcher_server]}#{API_VERSION}/auth"

      # payload
      payload = {
        app: {
          name: @client.app_info[:name],
          version: @client.app_info[:version],
          vendor: @client.app_info[:vendor],
          id: @client.app_info[:id]
        },
        permissions: @client.app_info[:permissions]
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
        File.open(@client.app_info[:conf_path], "w") { |f| f << JSON.pretty_generate(conf) }
      else
        # puts "ERROR #{res.code}: #{res.message}"
        response = nil
      end

      # return
      response
    end


    #
    # Check whether the authorisation token obtained from SAFE Launcher is still
    #  valid.
    #
    # Usage: my_client.auth.is_token_valid()
    # Fail: false
    # Success: true
    #
    # Reference: https://maidsafe.readme.io/docs/is-token-valid
    #
    def is_token_valid
      # entry point
      url = "#{@client.app_info[:launcher_server]}#{API_VERSION}/auth"

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
    # Revoke the authorisation token obtained from SAFE Launcher.
    #
    # Usage: my_client.auth.revoke_token()
    # Fail: false
    # Success: true
    #
    # Reference: https://maidsafe.readme.io/docs/revoke-token
    #
    def revoke_token
      # entry point
      url = "#{@client.app_info[:launcher_server]}#{API_VERSION}/auth"

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
    # Create a public or private directory either in the application's root
    #  directory or in SAFE Drive.
    # Only authorised requests can create a directory.
    #
    # Usage: my_client.nfs.create_directory("/photos")
    # Adv.Usage: my_client.nfs.create_directory("/photos", meta: "some meta", root_path: 'drive', is_private: true)
    # Fail: {"errorCode"=>-505, "description"=>"NfsError::FileAlreadyExistsWithSameName"}
    # Success: true
    #
    # Reference: https://maidsafe.readme.io/docs/nfs-create-directory
    #
    def create_directory(dir_path, options = {})
      # Default values
      options[:root_path]      = 'app' if ! options.has_key?(:root_path)
      options[:is_private]     = true  if ! options.has_key?(:is_private)

      # Entry point
      url = "#{@client.app_info[:launcher_server]}#{API_VERSION}/nfs/directory/#{options[:root_path]}/#{CGI.escape(dir_path)}"

      # Payload
      payload = {
        isPrivate: options[:is_private],
      }

      # Optional
      payload["metadata"] = Base64.strict_encode64(options[:meta]) if options.has_key?(:meta)

      # API call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Post.new(uri.path, {
        'Authorization' => "Bearer #{@client.key_helper.get_valid_token()}",
        'Content-Type' => 'application/json'
      })
      req.body = payload.to_json
      res = http.request(req)
      res.code == "200" ? true : JSON.parse(res.body)
    end

    # Alias
    def create_public_directory(dir_path, options = {})
      options[:is_private] = false
      self.create_directory(dir_path, options)
    end

    # Alias
    def create_private_directory(dir_path, options = {})
      options[:is_private] = true
      self.create_directory(dir_path, options)
    end

    #
    # Fetch a directory.
    # Only authorised requests can invoke this API.
    #
    # Usage: my_client.nfs.get_directory("/photos", root_path: 'drive')
    # Fail: {"errorCode"=>-1502, "description"=>"FfiError::PathNotFound"}
    # Success: {"info"=> {"name"=> "my_dir", ...}, ...}
    #
    # Reference: https://maidsafe.readme.io/docs/nfs-get-directory
    #
    def get_directory(dir_path, options = {})
      # Default values
      options[:root_path] = 'app' if ! options.has_key?(:root_path)

      # Entry point
      url = "#{@client.app_info[:launcher_server]}#{API_VERSION}/nfs/directory/#{options[:root_path]}/#{CGI.escape(dir_path)}"

      # API call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Get.new(uri.path, {
        'Authorization' => "Bearer #{@client.key_helper.get_valid_token()}",
      })
      res = http.request(req)
      JSON.parse(res.body)
    end


    #
    # Rename a directory and (optionally) update its metadata.
    # Only authorised requests can invoke this API.
    #
    # Rename: my_client.nfs.update_directory("/photos", name: "pics")
    # Change meta: my_client.nfs.update_directory("/photos", meta: "new meta")
    # Fail: {"errorCode"=>-505, "description"=>"NfsError::FileAlreadyExistsWithSameName"}
    # Success: true
    #
    # Reference: https://maidsafe.readme.io/docs/nfs-update-directory
    #
    def update_directory(dir_path, options = {})
      # Default values
      options[:root_path] = 'app' if ! options.has_key?(:root_path)

      # Entry point
      url = "#{@client.app_info[:launcher_server]}#{API_VERSION}/nfs/directory/#{options[:root_path]}/#{CGI.escape(dir_path)}"

      # Optional payload
      payload = {}
      payload["name"] = CGI.escape(options[:name]) if options.has_key?(:name)
      payload["metadata"] = Base64.strict_encode64(options[:meta]) if options.has_key?(:meta)

      # API call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Put.new(uri.path, {
        'Authorization' => "Bearer #{@client.key_helper.get_valid_token()}",
        'Content-Type' => 'application/json'
      })
      req.body = payload.to_json
      res = http.request(req)
      res.code == "200" ? true : JSON.parse(res.body)
    end

    # Alias
    def rename_directory(dir_path, new_name, options = {})
      options[:name] = new_name
      self.update_directory(dir_path, options)
    end

    #
    # Delete a directory.
    # Only authorised requests can invoke this API.
    #
    # Rename: my_client.nfs.delete_directory("/photos")
    # Change meta: my_client.nfs.delete_directory("/photos", root_path: "app")
    # Fail: {"errorCode"=>-505, "description"=>"NfsError::FileAlreadyExistsWithSameName"}
    # Success: true
    #
    # Reference: https://maidsafe.readme.io/docs/nfs-delete-directory
    #
    def delete_directory(dir_path, options = {})
      # Default values
      options[:root_path] = 'app' if ! options.has_key?(:root_path)

      # Entry point
      url = "#{@client.app_info[:launcher_server]}#{API_VERSION}/nfs/directory/#{options[:root_path]}/#{CGI.escape(dir_path)}"

      # API call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Delete.new(uri.path, {
        'Authorization' => "Bearer #{@client.key_helper.get_valid_token()}",
      })
      res = http.request(req)
      res.code == "200" ? true : JSON.parse(res.body)
    end


    #
    # Create a file.
    # Only authorised requests can invoke the API.
    #
    # Usage: my_client.nfs.create_file("/docs/hello.txt", "Hello World!")
    # Adv.Usage: my_client.nfs.create_file("/docs/hello.txt", meta: "some meta", root_path: "app", content_type: "text/plain")
    # Fail: {"errorCode"=>-505, "description"=>"NfsError::FileAlreadyExistsWithSameName"}
    # Success: true
    #
    # Reference: https://maidsafe.readme.io/docs/nfsfile
    #
    def create_file(file_path, contents, options = {})
      # Default values
      options[:root_path] = 'app' if ! options.has_key?(:root_path)
      contents ||= ""

      # Entry point
      url = "#{@client.app_info[:launcher_server]}#{API_VERSION}/nfs/file/#{options[:root_path]}/#{CGI.escape(file_path)}"

      # API call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      headers = {
        'Authorization' => "Bearer #{@client.key_helper.get_valid_token()}",
      }
      headers["Metadata"]       = Base64.strict_encode64(options[:meta]) if options.has_key?(:meta)
      headers["Content-Type"]   = options[:content_type] || 'text/plain'
      headers["Content-Length"] = contents.size.to_s
      req = Net::HTTP::Post.new(uri.path, headers)
      req.body = contents
      res = http.request(req)
      res.code == "200" ? true : JSON.parse(res.body)
    end


    #
    # Fetch the metadata of a file.
    # Only authorised requests can invoke the API.
    #
    # Usage: my_client.nfs.get_file_meta("/docs/hello.txt")
    # Adv.Usage: my_client.nfs.get_file_meta("/docs/hello.txt", root_path: "app")
    # Fail: {"errorCode"=>-505, "description"=>"NfsError::FileAlreadyExistsWithSameName"}
    # Success:
    #
    # Reference: https://maidsafe.readme.io/docs/nfs-get-file-metadata
    #
    def get_file_meta(file_path, options = {})
      # Default values
      options[:root_path] = 'app' if ! options.has_key?(:root_path)

      # Entry point
      url = "#{@client.app_info[:launcher_server]}#{API_VERSION}/nfs/file/#{options[:root_path]}/#{CGI.escape(file_path)}"

      # API call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      headers = {
        'Authorization' => "Bearer #{@client.key_helper.get_valid_token()}",
      }
      req = Net::HTTP::Head.new(uri.path, headers)
      res = http.request(req)
      res_headers = {}
      res.response.each_header {|k,v| res_headers[k] = v}
      res_headers["metadata"] = Base64.strict_decode64(res_headers["metadata"]) if res_headers.has_key?("metadata")
      res.code == "200" ? {"headers" => res_headers, "body" => res.body} : JSON.parse(res.body)
    end


    #
    # Read a file.
    # The file can be streamed in chunks and also fetched as partial content
    #  based on the range header specified in the request.
    # Only authorised requests can invoke the API.
    #
    # Usage: my_client.nfs.get_file("/docs/hello.txt")
    # Adv.Usage: my_client.nfs.get_file("/docs/hello.txt", range: "bytes 0-1000", root_path: "app")
    # Fail: {"errorCode"=>-1503, "description"=>"FfiError::InvalidPath"}
    # Success: {"headers"=>{"x-powered-by"=>"Express", "content-range"=>"bytes 0-4/4", "accept-ranges"=>"bytes", "content-length"=>"4", "created-on"=>"2016-08-14T12:51:18.924Z", "last-modified"=>"2016-08-14T12:51:18.935Z", "content-type"=>"text/plain", "date"=>"Sun, 14 Aug 2016 13:30:07 GMT", "connection"=>"close"}, "body"=>"Test"}
    #
    # Reference: https://maidsafe.readme.io/docs/nfs-get-file
    #
    def get_file(file_path, options = {})
      # Default values
      options[:offset]    = 0     if ! options.has_key?(:offset)
      options[:root_path] = 'app' if ! options.has_key?(:root_path)

      # Entry point
      url = "#{@client.app_info[:launcher_server]}#{API_VERSION}/nfs/file/#{options[:root_path]}/#{CGI.escape(file_path)}?"

      # Query params
      query = []
      query << "offset=#{options[:offset]}"
      query << "length=#{options[:length]}" if options.has_key?(:length) # length is optional
      url = "#{url}#{query.join('&')}"

      # API call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      headers = {
        'Authorization' => "Bearer #{@client.key_helper.get_valid_token()}",
      }
      headers["Range"] = options[:range] if options.has_key?(:range)
      req = Net::HTTP::Get.new(uri.path, headers)
      res = http.request(req)
      res_headers = {}
      res.response.each_header {|k,v| res_headers[k] = v}
      res.code == "200" ? {"headers" => res_headers, "body" => res.body} : JSON.parse(res.body)
    end


    #
    # Rename a file and (optionally) update its metadata.
    # Only authorised requests can invoke the API.
    #
    # Usage: my_client.nfs.update_file_metadata("/docs/hello.txt")
    # Adv.Usage: my_client.nfs.get_file("/docs/hello.txt", range: "bytes 0-1000", root_path: "app")
    # Fail: {"errorCode"=>-1503, "description"=>"FfiError::InvalidPath"}
    # Success: {"headers"=>{"x-powered-by"=>"Express", "content-range"=>"bytes 0-4/4", "accept-ranges"=>"bytes", "content-length"=>"4", "created-on"=>"2016-08-14T12:51:18.924Z", "last-modified"=>"2016-08-14T12:51:18.935Z", "content-type"=>"text/plain", "date"=>"Sun, 14 Aug 2016 13:30:07 GMT", "connection"=>"close"}, "body"=>"Test"}
    #
    # Reference: https://maidsafe.readme.io/docs/nfs-update-file-metadata
    #
    def update_file_meta(file_path, options = {})
      # Default values
      options[:root_path] = 'app' if ! options.has_key?(:root_path)

      # Entry point
      url = "#{@client.app_info[:launcher_server]}#{API_VERSION}/nfs/file/metadata/#{options[:root_path]}/#{CGI.escape(file_path)}"

      # Optional payload
      payload = {}
      payload["name"] = CGI.escape(options[:name]) if options.has_key?(:name)
      payload["metadata"] = Base64.strict_encode64(options[:meta]) if options.has_key?(:meta)

      # API call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Put.new(uri.path, {
        'Authorization' => "Bearer #{@client.key_helper.get_valid_token()}",
        'Content-Type' => 'application/json'
      })
      req.body = payload.to_json
      res = http.request(req)
      res.code == "200" ? true : JSON.parse(res.body)
    end

    # Alias
    def rename_file(file_path, new_name, options = {})
      options[:name] = new_name
      self.update_file_meta(file_path)
    end


    #
    # Delete a file.
    # Only authorised requests can invoke the API.
    #
    # Usage: my_client.nfs.delete_file("/docs/hello.txt")
    # Adv.Usage: my_client.nfs.delete_file("/docs/hello.txt", root_path: "app")
    # Fail: {"errorCode"=>-1503, "description"=>"FfiError::InvalidPath"}
    # Success: true
    #
    # Reference: https://maidsafe.readme.io/docs/nfs-delete-file
    #
    def delete_file(file_path, options = {})
      # Default values
      options[:root_path] = 'app' if ! options.has_key?(:root_path)

      # Entry point
      url = "#{@client.app_info[:launcher_server]}#{API_VERSION}/nfs/file/#{options[:root_path]}/#{CGI.escape(file_path)}"

      # API call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Delete.new(uri.path, {
        'Authorization' => "Bearer #{@client.key_helper.get_valid_token()}",
      })
      res = http.request(req)
      res.code == "200" ? true : JSON.parse(res.body)
    end
  end


  class DNS
    def initialize(client_obj)
      @client = client_obj
    end

    #
    # Register a long name. Long names are public names that can be shared.
    # Only authorised requests can invoke the API.
    #
    # Usage: my_client.dns.create_long_name("my-domain")
    # Fail: {"errorCode"=>-1503, "description"=>"FfiError::InvalidPath"}
    # Success: true
    #
    # Reference: https://maidsafe.readme.io/docs/dns-create-long-name
    #
    def create_long_name(long_name)
      # entry point
      url = "#{@client.app_info[:launcher_server]}#{API_VERSION}/dns/#{CGI.escape(long_name)}"

      # api call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Post.new(uri.path, {
        'Authorization' => "Bearer #{@client.key_helper.get_valid_token()}",
        'Content-Type' => 'text/plain'
      })
      res = http.request(req)
      res.code == "200" ? true : JSON.parse(res.body)
    end


    #
    # Register a long name and a service.
    # Only authorised requests can invoke the API.
    #
    # Usage: my_client.dns.register_service("my-domain", "www", "/sources")
    # Fail: {"errorCode"=>-1503, "description"=>"FfiError::InvalidPath"}
    # Success: true
    #
    # Reference: https://maidsafe.readme.io/docs/dns-register-service
    #
    def register_service(long_name, service_name, service_home_dir_path, options = {})
      # Entry point
      url = "#{@client.app_info[:launcher_server]}#{API_VERSION}/dns"

      # Payload
      payload = {
        longName: long_name,
        serviceName: service_name,
        rootPath: 'app',
        serviceHomeDirPath: service_home_dir_path,
      }

      # Optional
      payload["metadata"] = options[:meta] if options.has_key?(:meta)

      # API call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Post.new(uri.path, {
        'Authorization' => "Bearer #{@client.key_helper.get_valid_token()}",
        'Content-Type' => 'application/json'
      })
      req.body = payload.to_json
      res = http.request(req)
      res.code == "200" ? true : JSON.parse(res.body)
    end


    #
    # Add a service to a registered long name.
    # Only authorised requests can invoke the API.
    #
    # Usage: my_client.dns.add_service("my-domain", "www", "/sources")
    # Fail: {"errorCode"=>-1503, "description"=>"FfiError::InvalidPath"}
    # Success: true
    #
    # Reference: https://maidsafe.readme.io/docs/dns
    #
    def add_service(long_name, service_name, service_home_dir_path)
      # Entry point
      url = "#{@client.app_info[:launcher_server]}#{API_VERSION}/dns"

      # Payload
      payload = {
        longName: long_name,
        serviceName: service_name,
        rootPath: 'app',
        serviceHomeDirPath: service_home_dir_path,
      }

      # API call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Put.new(uri.path, {
        'Authorization' => "Bearer #{@client.key_helper.get_valid_token()}",
        'Content-Type' => 'application/json'
      })
      req.body = payload.to_json
      res = http.request(req)
      res.code == "200" ? true : JSON.parse(res.body)
    end


    # https://maidsafe.readme.io/docs/dns-list-long-names
    def list_long_names
      # entry point
      url = "#{@client.app_info[:launcher_server]}#{API_VERSION}/dns"

      # api call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Get.new(uri.path, {
        'Authorization' => "Bearer #{@client.key_helper.get_valid_token()}",
      })
      res = http.request(req)
      JSON.parse(res.body)
    end

    # https://maidsafe.readme.io/docs/dns-list-services
    def list_services(long_name)
      # entry point
      url = "#{@client.app_info[:launcher_server]}#{API_VERSION}/dns/#{CGI.escape(long_name)}"

      # api call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Get.new(uri.path, {
        'Authorization' => "Bearer #{@client.key_helper.get_valid_token()}",
      })
      res = http.request(req)
      JSON.parse(res.body)
    end


    # https://maidsafe.readme.io/docs/dns-get-home-dir
    def get_home_dir(long_name, service_name)
      # entry point
      url = "#{@client.app_info[:launcher_server]}#{API_VERSION}/dns/#{CGI.escape(service_name)}/#{CGI.escape(long_name)}"

      # api call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Get.new(uri.path)
      res = http.request(req)
      res = JSON.parse(res.body)
      res["info"]["metadata"] = Base64.strict_decode64(res["info"]["metadata"]) if res.has_key?("info") && res["info"].has_key?("metadata")
      res
    end


    # https://maidsafe.readme.io/docs/dns-get-file-unauth
    # get_file_unauth("thegoogle", "www", "index.html")
    def get_file_unauth(long_name, service_name, file_path)
      # entry point
      url = "#{@client.app_info[:launcher_server]}#{API_VERSION}/dns/#{CGI.escape(service_name)}/#{CGI.escape(long_name)}/#{CGI.escape(file_path)}"

      # api call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Get.new(uri.path)
      res = http.request(req)
      res_headers = {}
      res.response.each_header {|k,v| res_headers[k] = v}
      res.code == "200" ? {"headers" => res_headers, "body" => res.body} : JSON.parse(res.body)
    end
  end

  class AD
    def initialize(client_obj)
      @client = client_obj
    end

    def create(name, is_private = false, filter_type = 'BLACK_LIST', filter_key = nil)
      # Entry point
      url = "#{@client.app_info[:launcher_server]}#{API_VERSION}/appendable-data"

      # Payload
      payload = {
        name: name,
        isPrivate: is_private,
        filterType: filter_type,
        filterKey: filter_key
      }

      # API call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Post.new(uri.path, {
        'Authorization' => "Bearer #{@client.key_helper.get_valid_token()}",
        'Content-Type' => 'application/json'
      })
      req.body = payload.to_json
      res = http.request(req)
      res.code == "200" ? JSON.parse(res.body)['handleId'] : JSON.parse(res.body)
    end

    def put(handle_id)
      # Entry point
      url = "#{@client.app_info[:launcher_server]}#{API_VERSION}/appendable-data/#{handle_id}"

      # API call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Put.new(uri.path, {
        'Authorization' => "Bearer #{@client.key_helper.get_valid_token()}"
      })
      res = http.request(req)
      res.code == "200" ? true : JSON.parse(res.body)
    end

    def post(handle_id)
      # Entry point
      url = "#{@client.app_info[:launcher_server]}#{API_VERSION}/appendable-data/#{handle_id}"

      # API call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Post.new(uri.path, {
        'Authorization' => "Bearer #{@client.key_helper.get_valid_token()}"
      })
      res = http.request(req)
      res.code == "200" ? true : JSON.parse(res.body)
    end

    def get_handle(data_id_handle)
      # entry point
      url = "#{@client.app_info[:launcher_server]}#{API_VERSION}/appendable-data/handle/#{data_id_handle}"

      # api call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Get.new(uri.path, {
        'Authorization' => "Bearer #{@client.key_helper.get_token()}"
      })
      res = http.request(req)
      JSON.parse(res.body)
    end

    def get_data_id_handle(handle_id)
      # entry point
      url = "#{@client.app_info[:launcher_server]}#{API_VERSION}/appendable-data/data-id/#{handle_id}"

      # api call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Get.new(uri.path, {
        'Authorization' => "Bearer #{@client.key_helper.get_token()}"
      })
      res = http.request(req)
      res.code == "200" ? JSON.parse(res.body)['handleId'] : JSON.parse(res.body)
    end

    def get_metadata(handle_id)
      # entry point
      url = "#{@client.app_info[:launcher_server]}#{API_VERSION}/appendable-data/metadata/#{handle_id}"

      # api call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Get.new(uri.path, {
        'Authorization' => "Bearer #{@client.key_helper.get_token()}"
      })
      res = http.request(req)
      JSON.parse(res.body)
    end

    def drop_handle(handle_id)
      # entry point
      url = "#{@client.app_info[:launcher_server]}#{API_VERSION}/appendable-data/handle/#{handle_id}"

      # api call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Delete.new(uri.path)
      res = http.request(req)
      res.code == "200" ? true : JSON.parse(res.body)
    end

    def append(handle_id, handle_data_id)
      # Entry point
      url = "#{@client.app_info[:launcher_server]}#{API_VERSION}/appendable-data/#{handle_id}/#{handle_data_id}"

      # API call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Put.new(uri.path, {
        'Authorization' => "Bearer #{@client.key_helper.get_valid_token()}"
      })
      res = http.request(req)
      res.code == "200" ? true : JSON.parse(res.body)
    end

    def get_data_id_at_index(handle_id, index)
      # Entry point
      url = "#{@client.app_info[:launcher_server]}#{API_VERSION}/appendable-data/#{handle_id}/#{index}"

      # API call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Get.new(uri.path, {
        'Authorization' => "Bearer #{@client.key_helper.get_valid_token()}"
      })
      res = http.request(req)
      res.code == "200" ? JSON.parse(res.body)["handleId"] : JSON.parse(res.body)
    end

  end

  class SD
    def initialize(client_obj)
      @client = client_obj
    end

    def create_sd(name, type_tag = 500, hnd_cipher_opts = nil, data = nil, version = 0)
      # Entry point
      url = "#{@client.app_info[:launcher_server]}#{API_VERSION}/structured-data"

      # Payload
      payload = {
        name: name,
        typeTag: type_tag,
        cipherOpts: hnd_cipher_opts,
        data: Base64.encode64(data),
        version: version
      }

      # API call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Post.new(uri.path, {
        'Authorization' => "Bearer #{@client.key_helper.get_valid_token()}",
        'Content-Type' => 'application/json'
      })
      req.body = payload.to_json
      res = http.request(req)
      res.code == "200" ? JSON.parse(res.body)['handleId'] : JSON.parse(res.body)
    end


    def put(handle_id)
      # Entry point
      url = "#{@client.app_info[:launcher_server]}#{API_VERSION}/structured-data/#{handle_id}"

      # API call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Put.new(uri.path, {
        'Authorization' => "Bearer #{@client.key_helper.get_valid_token()}"
      })
      res = http.request(req)
      res.code == "200" ? true : JSON.parse(res.body)
    end

    def post(handle_id)
      # Entry point
      url = "#{@client.app_info[:launcher_server]}#{API_VERSION}/structured-data/#{handle_id}"

      # API call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Post.new(uri.path, {
        'Authorization' => "Bearer #{@client.key_helper.get_valid_token()}"
      })
      res = http.request(req)
      res.code == "200" ? true : JSON.parse(res.body)
    end

    def get_handle(data_id_handle)
      # entry point
      url = "#{@client.app_info[:launcher_server]}#{API_VERSION}/structured-data/handle/#{data_id_handle}"

      # api call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Get.new(uri.path, {
        'Authorization' => "Bearer #{@client.key_helper.get_token()}"
      })
      res = http.request(req)
      JSON.parse(res.body)
    end

    def get_data_id_handle(handle_id)
      # entry point
      url = "#{@client.app_info[:launcher_server]}#{API_VERSION}/structured-data/data-id/#{handle_id}"

      # api call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Get.new(uri.path, {
        'Authorization' => "Bearer #{@client.key_helper.get_token()}"
      })
      res = http.request(req)
      JSON.parse(res.body)
    end

    def get_metadata(handle_id)
      # entry point
      url = "#{@client.app_info[:launcher_server]}#{API_VERSION}/structured-data/metadata/#{handle_id}"

      # api call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Get.new(uri.path, {
        'Authorization' => "Bearer #{@client.key_helper.get_token()}"
      })
      res = http.request(req)
      JSON.parse(res.body)
    end

    def read_data(handle_id, version = nil)
      # entry point
      url = "#{@client.app_info[:launcher_server]}#{API_VERSION}/structured-data/#{handle_id}"
      url = "#{url}/#{version}?" if ! version.nil?

      # api call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Get.new(uri.path, {
        'Authorization' => "Bearer #{@client.key_helper.get_token()}"
      })
      res = http.request(req)
      res.code == "200" ? res.body : JSON.parse(res.body)
    end

    def drop_handle(handle_id)
      # entry point
      url = "#{@client.app_info[:launcher_server]}#{API_VERSION}/structured-data/handle/#{handle_id}"

      # api call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Delete.new(uri.path)
      res = http.request(req)
      res.code == "200" ? true : JSON.parse(res.body)
    end

    def create(name, contents, type = 500)
      name = name.is_a?(String) ? SafeNet::s2b(name) : name

      # plain (not encrypted)
      hnd_cipher = @client.cipher.get_handle

      # create
      hnd = @client.sd.create_sd(name, type, hnd_cipher, contents)
      res = @client.sd.put(hnd) # saves on the network
      @client.sd.drop_handle(hnd) # release handler

      # release cipher handler
      @client.cipher.drop_handle(hnd_cipher)

      res
    end

    def read(name, type = 500)
      name = name.is_a?(String) ? SafeNet::s2b(name) : name

      hnd_sd_data_id = @client.data_id.get_data_id_sd(name)
      hnd_sd = @client.sd.get_handle(hnd_sd_data_id)['handleId']
      contents = @client.sd.read_data(hnd_sd)
      @client.sd.drop_handle(hnd_sd)
      @client.data_id.drop_handle(hnd_sd_data_id)

      contents
    end

    def update(name, contents, type = 500)
      name = name.is_a?(String) ? SafeNet::s2b(name) : name

      # plain (not encrypted)
      hnd_cipher = @client.cipher.get_handle

      # create
      hnd = @client.sd.create_sd(name, type, hnd_cipher, contents)
      res = @client.sd.post(hnd) # saves on the network
      @client.sd.drop_handle(hnd) # release handler

      # release cipher handler
      @client.cipher.drop_handle(hnd_cipher)

      res
    end
  end

  class Immutable
    def initialize(client_obj)
      @client = client_obj
    end

    def get_reader_handle(handle_id)
      # entry point
      url = "#{@client.app_info[:launcher_server]}#{API_VERSION}/immutable-data/reader/#{handle_id}"

      # api call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Get.new(uri.path, {
        'Authorization' => "Bearer #{@client.key_helper.get_token()}"
      })
      res = http.request(req)
      res.code == "200" ? JSON.parse(res.body)["handleId"] : JSON.parse(res.body)
    end

    def get_writer_handle()
      # entry point
      url = "#{@client.app_info[:launcher_server]}#{API_VERSION}/immutable-data/writer"

      # api call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Get.new(uri.path, {
        'Authorization' => "Bearer #{@client.key_helper.get_token()}"
      })
      res = http.request(req)
      res.code == "200" ? JSON.parse(res.body)["handleId"] : JSON.parse(res.body)
    end

    # eg range: "bytes=0-1000"
    def read_data(handle_id, range = nil)
      # entry point
      url = "#{@client.app_info[:launcher_server]}#{API_VERSION}/immutable-data/#{handle_id}"

      # api call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      header = { 'Authorization' => "Bearer #{@client.key_helper.get_token()}", 'Content-Type': 'text/plain' }
      header['Range'] = range if range
      req = Net::HTTP::Get.new(uri.path, header)
      res = http.request(req)
      (res.code == "200" || res.code == "206") ? res.body : JSON.parse(res.body)
    end

    def write_data(handle_id, contents)
      # Entry point
      url = "#{@client.app_info[:launcher_server]}#{API_VERSION}/immutable-data/#{handle_id}"

      # API call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      headers = {
        'Authorization' => "Bearer #{@client.key_helper.get_valid_token()}",
        'Content-Type': 'text/plain'
      }
      headers["Content-Length"] = contents.size.to_s
      req = Net::HTTP::Post.new(uri.path, headers)
      req.body = contents
      res = http.request(req)
      res.code == "200" ? true : JSON.parse(res.body)
    end

    def close_writer(handle_id, cipher_opts_handle)
      # entry point
      url = "#{@client.app_info[:launcher_server]}#{API_VERSION}/immutable-data/#{handle_id}/#{cipher_opts_handle}"

      # api call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Put.new(uri.path, {
        'Authorization' => "Bearer #{@client.key_helper.get_valid_token()}"
      })
      res = http.request(req)
      res.code == "200" ? JSON.parse(res.body)["handleId"] : JSON.parse(res.body)
    end


    def drop_reader_handle(handle_id)
      # entry point
      url = "#{@client.app_info[:launcher_server]}#{API_VERSION}/immutable-data/reader/#{handle_id}"

      # api call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Delete.new(uri.path, {
        'Authorization' => "Bearer #{@client.key_helper.get_valid_token()}"
      })
      res = http.request(req)
      res.code == "200" ? true : JSON.parse(res.body)
    end

    def drop_writer_handle(handle_id)
      # entry point
      url = "#{@client.app_info[:launcher_server]}#{API_VERSION}/immutable-data/writer/#{handle_id}"

      # api call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Delete.new(uri.path, {
        'Authorization' => "Bearer #{@client.key_helper.get_valid_token()}"
      })
      res = http.request(req)
      res.code == "200" ? true : JSON.parse(res.body)
    end

    # helper
    def write(contents)
      # plain (not encrypted)
      hnd_cipher = @client.cipher.get_handle

      # write
      hnd_w = @client.immutable.get_writer_handle
      @client.immutable.write_data(hnd_w, contents)
      hnd_data_id = @client.immutable.close_writer(hnd_w, hnd_cipher)
      name = @client.data_id.serialize(hnd_data_id)
      @client.immutable.drop_writer_handle(hnd_w)
      @client.data_id.drop_handle(hnd_data_id)

      # release cipher handler
      @client.cipher.drop_handle(hnd_cipher)

      name
    end

    # helper
    def read(name, chunk_pos = nil, max_chunk_size = 1_000_000)
      hnd_data_id = @client.data_id.deserialize(name)
      hnd_r = @client.immutable.get_reader_handle(hnd_data_id)
      contents = if chunk_pos
        @client.immutable.read_data(hnd_r, "bytes=#{chunk_pos}-#{chunk_pos+max_chunk_size}")
      else
        @client.immutable.read_data(hnd_r)
      end
      @client.immutable.drop_reader_handle(hnd_r)
      @client.data_id.drop_handle(hnd_data_id)

      contents
    end
  end

  class Cipher
    def initialize(client_obj)
      @client = client_obj
    end

    def get_handle(enc_type = 'PLAIN', sym_key_handle = nil)
      # Entry point
      url = "#{@client.app_info[:launcher_server]}#{API_VERSION}/cipher-opts/#{enc_type}"
      url << "/#{sym_key_handle}?" if sym_key_handle

      # API call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Get.new(uri.path, {
        'Authorization' => "Bearer #{@client.key_helper.get_valid_token()}"
      })
      res = http.request(req)
      res.code == "200" ? JSON.parse(res.body)["handleId"] : JSON.parse(res.body)
    end

    def drop_handle(handle_id)
      # entry point
      url = "#{@client.app_info[:launcher_server]}#{API_VERSION}/cipher-opts/#{handle_id}"

      # api call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Delete.new(uri.path, {
        'Authorization' => "Bearer #{@client.key_helper.get_valid_token()}"
      })
      res = http.request(req)
      res.code == "200" ? true : JSON.parse(res.body)
    end
  end

  class DataId
    def initialize(client_obj)
      @client = client_obj
    end

    def get_data_id_sd(name, type_tag = 500)
      # Entry point
      url = "#{@client.app_info[:launcher_server]}#{API_VERSION}/data-id/structured-data"

      # Payload
      payload = {
        name: name,
        typeTag: type_tag
      }

      # API call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Post.new(uri.path, {
        'Authorization' => "Bearer #{@client.key_helper.get_valid_token()}",
        'Content-Type' => 'application/json'
      })
      req.body = payload.to_json
      res = http.request(req)
      res.code == "200" ? JSON.parse(res.body)['handleId'] : JSON.parse(res.body)
    end

    def get_data_id_ad(name, is_private = false)
      # Entry point
      url = "#{@client.app_info[:launcher_server]}#{API_VERSION}/data-id/appendable-data"

      # Payload
      payload = {
        name: name,
        isPrivate: is_private
      }

      # API call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Post.new(uri.path, {
        'Authorization' => "Bearer #{@client.key_helper.get_valid_token()}",
        'Content-Type' => 'application/json'
      })
      req.body = payload.to_json
      res = http.request(req)
      res.code == "200" ? JSON.parse(res.body)['handleId'] : JSON.parse(res.body)
    end

    def drop_handle(handle_id)
      # entry point
      url = "#{@client.app_info[:launcher_server]}#{API_VERSION}/data-id/#{handle_id}"

      # api call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Delete.new(uri.path, {
        'Authorization' => "Bearer #{@client.key_helper.get_valid_token()}"
      })
      res = http.request(req)
      res.code == "200" ? true : JSON.parse(res.body)
    end

    def serialize(handle_id)
      # entry point
      url = "#{@client.app_info[:launcher_server]}#{API_VERSION}/data-id/#{handle_id}"

      # api call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      req = Net::HTTP::Get.new(uri.path, {
        'Authorization' => "Bearer #{@client.key_helper.get_valid_token()}"
      })
      res = http.request(req)
      res.code == "200" ? res.body : JSON.parse(res.body)
    end

    def deserialize(contents)
      # entry point
      url = "#{@client.app_info[:launcher_server]}#{API_VERSION}/data-id"

      # api call
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      headers = {
        'Authorization' => "Bearer #{@client.key_helper.get_valid_token()}",
        'Content-Type': 'text/plain'
      }
      headers["Content-Length"] = contents.size.to_s
      req = Net::HTTP::Post.new(uri.path, headers)
      req.body = contents
      res = http.request(req)
      res.code == "200" ? JSON.parse(res.body)['handleId'] : JSON.parse(res.body)
    end

  end

  def self.quick_start(low_level_api = true, safe_drive_access = true)
    permissions = []
    permissions << 'LOW_LEVEL_API' if low_level_api
    permissions << 'SAFE_DRIVE_ACCESS' if safe_drive_access
    SafeNet::Client.new(permissions: permissions)
  end

  def self.s2b(str)
    # Digest::SHA2.new(256).hexdigest(str)
    Digest::SHA2.new(256).base64digest(str)
  end

  def self.bin_name(str)
    BinName.new(str)
  end

  class BinName
    def initializer(str)
      @value = str
    end

    def to_s
      @value
    end
  end
end
