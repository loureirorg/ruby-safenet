# Ruby-Safenet

A simple SAFE API wrapper written in Ruby.

## Installation
```
  $ gem install safenet
```

## Usage

```ruby
require "safenet"

my_client = SafeNet::Client.new
my_client.nfs.create_directory("/mydir", is_private: false)
my_client.nfs.file("/mydir/index.html", is_private: false)
my_client.nfs.update_file_content("/mydir/index.html", "Hello world!<br>I'm a webpage :D")
my_client.dns.register_service("my-wonderful-app", "www", "/mydir")
my_client.dns.get_file("/mydir/index.html")

# Then, open http://www.my-wonderful-app.safenet/
```

You can also set a more detailed App info:
```
my_client = SafeNet::Client.new({
  name:      "Ruby Demo App",
  version:   "0.0.1",
  vendor:    "Vendor's Name",
  id:        "org.thevendor.demo",
})
```

*File Upload / Download:*
```ruby
# upload
my_client.nfs.file("/mydir/dog.jpg")
my_client.nfs.update_file_content("/mydir/dog.jpg", File.read("/home/daniel/Pictures/dog.jpg"))

# download
File.open("/home/daniel/Pictures/dog-new.jpg", "w") do |file|
  file.write(my_client.nfs.get_file("/mydir/dog.jpg"))
end
```

*Directory's file list:*
```ruby
my_client.nfs.get_directory("/mydir")["files"].each do |file|
  puts file["name"]
end
```

## Supported methods:
|Module|Method|Arguments|Optional|Doc|
|------|------|---------|--------|---|
|nfs|create_directory|dir_path|is_private, is_versioned, is_path_shared|Reference: https://maidsafe.readme.io/docs/nfs-create-directory|
|nfs|get_directory|dir_path|is_path_shared|https://maidsafe.readme.io/docs/nfs-get-directory|
|nfs|delete_directory|dir_path|is_path_shared|https://maidsafe.readme.io/docs/nfs-create-directory|
|nfs|file|file_path|is_private, is_versioned, is_path_shared|https://maidsafe.readme.io/docs/nfsfile|
|nfs|get_file|file_path|is_path_shared, offset, length|https://maidsafe.readme.io/docs/nfs-get-file|
|nfs|update_file_content|file_path, contents|is_path_shared, offset|https://maidsafe.readme.io/docs/nfs-update-file-content|
|nfs|delete_file|file_path|is_path_shared|https://maidsafe.readme.io/docs/nfs-delete-file|
|dns|create_long_name|long_name||https://maidsafe.readme.io/docs/dns-create-long-name|
|dns|register_service|long_name, service_name, service_home_dir_path|is_path_shared, metadata|https://maidsafe.readme.io/docs/dns-register-service|
|dns|list_long_names||is_path_shared, metadata|https://maidsafe.readme.io/docs/dns-list-long-names|
|dns|list_services|long_name||https://maidsafe.readme.io/docs/dns-list-services|
|dns|get_home_dir|long_name, service_name||https://maidsafe.readme.io/docs/dns-get-home-dir|
|dns|get_file_unauth|long_name, service_name, file_path|offset, length|https://maidsafe.readme.io/docs/dns-get-file-unauth|
