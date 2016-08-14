# Ruby-Safenet

A simple SAFE API wrapper written in Ruby.

**Tested Aug 14, 2016. Working with SAFE version 0.5.**

## Installation
```
  $ gem install ruby-safenet
```

## Usage

```ruby
require "safenet"

my_client = SafeNet::Client.new
my_client.nfs.create_public_directory("/mydir")
my_client.nfs.create_file("/mydir/index.html", "Hello world!<br>I'm a webpage :D")
my_client.dns.register_service("my-wonderful-app", "www", "/mydir")
my_client.nfs.get_file("/mydir/index.html")

# Then, open http://www.my-wonderful-app.safenet/
```

You can also set a more detailed App info:
```
my_client = SafeNet::Client.new({
  name:      "Ruby Demo App",
  version:   "0.0.1",
  vendor:    "Vendor's Name",
  id:        "thevendor.demo",
})
```

*File Upload / Download:*
```ruby
# upload
my_client.nfs.create_file("/mydir/dog.jpg", File.read("/home/daniel/Pictures/dog.jpg"), content_type: "image/jpeg")

# download
File.open("/home/daniel/Pictures/dog-new.jpg", "w") do |file|
  file.write(my_client.nfs.get_file("/mydir/dog.jpg")["body"])
end
```

*Directory's file list:*
```ruby
my_client.nfs.get_directory("/mydir")["files"].each do |file|
  puts file["name"]
end
```

## Structured Data (SD): **EMULATED**
Although SD has not been officially implemented by MaidSafe yet, we provide a sub-module (sd) that emulates it.
All the information are stored in the Safe Network, through DNS/NFS sub-systems.

Example:
```ruby
my_client.sd.update(37267, 11, "Hi John") # 37267 = id, 11 = tag_type
my_client.sd.get(37267, 11)
my_client.sd.update(37267, 11, "Hello World!")

my_client.raw.create("Hello World!") # => "861844d6704e8573fec34d967e20bcfef3d424cf48be04e6dc08f2bd58c729743371015ead891cc3cf1c9d34b49264b510751b1ff9e537937bc46b5d6ff4ecc8"
my_client.raw.create_from_file("/home/daniel/dog.jpg")
my_client.raw.get("861844d6704e8573fec34d967e20bcfef3d424cf48be04e6dc08f2bd58c729743371015ead891cc3cf1c9d34b49264b510751b1ff9e537937bc46b5d6ff4ecc8") # => "Hello World!"
```

Encryption and versioning are both not supported in this emulated version.

For more information see:
https://github.com/maidsafe/rfcs/blob/master/text/0028-launcher-low-level-api/0028-launcher-low-level-api.md

## Supported methods:
|Module|Method|Arguments|Optional|Doc|
|------|------|---------|--------|---|
|sd|update|id (_int_), tag_type (_int_), contents (_string_\|_binary_)|||
|sd|get|id (_int_), tag_type (_int_)|||
|nfs|create_public_directory|dir_path (_string_)|root_path ("_app_" or "_drive_"), meta (_string_)|* _Alias to "create_directory"_|
|nfs|create_private_directory|dir_path (_string_)|root_path ("_app_" or "_drive_"), meta (_string_)|* _Alias to "create_directory"_|
|nfs|create_directory|dir_path (_string_)|is_private (_bool_), root_path ("_app_" or "_drive_"), meta (_string_)|https://maidsafe.readme.io/docs/nfs-create-directory|
|nfs|get_directory|dir_path (_string_)|root_path ("_app_" or "_drive_")|https://maidsafe.readme.io/docs/nfs-get-directory|
|nfs|rename_directory|dir_path (_string_), new_name (_string_)|root_path ("_app_" or "_drive_")|* _Alias to update_directory_|
|nfs|update_directory|dir_path (_string_)|root_path ("_app_" or "_drive_"), meta (_string_), name (_string_)|https://maidsafe.readme.io/docs/nfs-update-directory|
|nfs|delete_directory|dir_path (_string_)|root_path ("_app_" or "_drive_")|https://maidsafe.readme.io/docs/nfs-create-directory|
|nfs|create_file|file_path (_string_), contents (_string_ \| _binary_)|root_path ("_app_" or "_drive_"), meta (_string_), content_type (_string_)|https://maidsafe.readme.io/docs/nfsfile|
|nfs|get_file|file_path (_string_)|root_path ("_app_" or "_drive_"), offset (_int_), length (_int_), range (eg. "bytes 0-1000")|https://maidsafe.readme.io/docs/nfs-get-file|
|nfs|rename_file|file_path (_string_), new_name (_string_)|root_path ("_app_" or "_drive_"), meta (_string_)|* Alias to "update_file_meta"|
|nfs|update_file_meta|file_path (_string_)|root_path ("_app_" or "_drive_"), meta (_string_), name (_string_)|https://maidsafe.readme.io/docs/nfs-update-file-metadata|
|nfs|delete_file|file_path (_string_)|root_path ("_app_" or "_drive_")|https://maidsafe.readme.io/docs/nfs-delete-file|
|dns|create_long_name|long_name (_string_)||https://maidsafe.readme.io/docs/dns-create-long-name|
|dns|register_service|long_name (_string_), service_name (_string_), service_home_dir_path (_string_)||https://maidsafe.readme.io/docs/dns-register-service|
|dns|add_service|long_name (_string_), service_name (_string_), service_home_dir_path (_string_)||https://maidsafe.readme.io/docs/dns|
|dns|list_long_names||root_path ("_app_" or "_drive_")|https://maidsafe.readme.io/docs/dns-list-long-names|
|dns|list_services|long_name (_string_)||https://maidsafe.readme.io/docs/dns-list-services|
|dns|get_home_dir|long_name (_string_), service_name (_string_)||https://maidsafe.readme.io/docs/dns-get-home-dir|
|dns|get_file_unauth|long_name (_string_), service_name (_string_), file_path (_string_)||https://maidsafe.readme.io/docs/dns-get-file-unauth|
