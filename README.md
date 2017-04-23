# Ruby-Safenet

A simple SAFE API wrapper written in Ruby.

**Tested Feb 24, 2017. Working with SAFE version 0.5.**

## Installation
```
  $ gem install ruby-safenet
```

## Usage

```ruby
require "safenet"

safe = SafeNet::Client.new(permissions: ["SAFE_DRIVE_ACCESS"])
safe.nfs.create_public_directory("/mydir")
safe.nfs.create_file("/mydir/index.html", "Hello world!<br>I'm a webpage :D")
safe.dns.register_service("my-wonderful-app", "www", "/mydir")
safe.nfs.get_file("/mydir/index.html")

# Then, open safe://www.my-wonderful-app/
```

You can also set a more detailed App info:
```
safe = SafeNet::Client.new({
  name:      "Ruby Demo App",
  version:   "0.0.1",
  vendor:    "Vendor's Name",
  id:        "thevendor.demo",
})
```

*File Upload / Download:*
```ruby
# upload
safe.nfs.create_file("/mydir/dog.jpg", File.read("/home/daniel/Pictures/dog.jpg"), content_type: "image/jpeg")

# download
File.open("/home/daniel/Pictures/dog-new.jpg", "w") do |file|
  file.write(safe.nfs.get_file("/mydir/dog.jpg")["body"])
end
```

*Directory's file list:*
```ruby
safe.nfs.get_directory("/mydir")["files"].each do |file|
  puts file["name"]
end
```

## Structured Data (SD) - With helpers:

```ruby
safe = safenet_quick

safe.sd.create('my_sd', 'Hello SD!')
puts safe.sd.read('my_sd') # Hello SD!

safe.sd.update('my_sd', 'Hello SD 2!')
puts safe.sd.read('my_sd') # Hello SD 2!
```

## Immutable Data - With helpers:
```ruby
# client
safe = safenet_quick

# write / read
name = safe.immutable.create('Hello SD') # name = base64 encoded
puts safe.immutable.read(name)

# write from file
name = safe.immutable.create_from_file("#{Rails.root}/my_file.txt")
safe.immutable.dump(name, "#{Rails.root}/from_safenet.txt")
```

## Structured Data (SD) - With safe primitives:

```ruby
# client
safe = SafeNet::Client.new(permissions: ["LOW_LEVEL_API"])

# plain (not encrypted)
hnd_cipher = safe.cipher.get_handle

# create
name = SafeNet::s2b('my_sd')
hnd = safe.sd.create_sd(name, 500, hnd_cipher, IO.binread("#{Rails.root}/my_file.txt"))
safe.sd.put(hnd) # saves on the network
safe.sd.drop_handle(hnd) # release handler

# release cipher handler
safe.cipher.drop_handle(hnd_cipher)

# read
name = SafeNet::s2b('my_sd')
hnd_sd_data_id = safe.data_id.get_data_id_sd(name)
hnd_sd = safe.sd.get_handle(hnd_sd_data_id)['handleId']
contents = safe.sd.read_data(hnd_sd)
safe.sd.drop_handle(hnd_sd)
safe.data_id.drop_handle(hnd_sd_data_id)
puts contents # print SD contents on screen
```

## Immutable Data - With safe primitives:

```ruby
# client
safe = SafeNet::Client.new(permissions: ["LOW_LEVEL_API"])

# plain (not encrypted)
hnd_cipher = safe.cipher.get_handle

# write
hnd_w = safe.immutable.get_writer_handle
safe.immutable.write_data(hnd_w, 'Hello World')
hnd_data_id = safe.immutable.close_writer(hnd_w, hnd_cipher)
name = safe.data_id.serialize(hnd_data_id) # IMMUTABLE NAME
safe.immutable.drop_writer_handle(hnd_w)
safe.data_id.drop_handle(hnd_data_id)
puts "Immutable name:\n  * Binary: #{name}\n  * Hex...: #{name.unpack("H*").first}\n  * Base64: #{Base64.encode64(name)}"

# release cipher handler
safe.cipher.drop_handle(hnd_cipher)

# read
hnd_data_id = safe.data_id.deserialize(name)
hnd_r = safe.immutable.get_reader_handle(hnd_data_id)
contents = safe.immutable.read_data(hnd_r)
safe.immutable.drop_reader_handle(hnd_r)
safe.data_id.drop_handle(hnd_data_id)
puts contents

# read - seek position
chunk_pos = 0
max_chunk_size = 100_000

hnd_data_id = safe.data_id.deserialize(name)
hnd_r = safe.immutable.get_reader_handle(hnd_data_id)
contents = safe.immutable.read_data(hnd_r, "bytes=#{chunk_pos}-#{chunk_pos+max_chunk_size}")
safe.immutable.drop_reader_handle(hnd_r)
safe.data_id.drop_handle(hnd_data_id)
puts contents
```

## Supported methods:
|Module|Method|Arguments|Optional|Doc|
|------|------|---------|--------|---|
|nfs|create_public_directory|dir_path (_string_)|root_path ("_app_" or "_drive_"), meta (_string_)|* _Alias to "create_directory"_|
|nfs|create_private_directory|dir_path (_string_)|root_path ("_app_" or "_drive_"), meta (_string_)|* _Alias to "create_directory"_|
|nfs|create_directory|dir_path (_string_)|is_private (_bool_), root_path ("_app_" or "_drive_"), meta (_string_)|https://maidsafe.readme.io/docs/nfs-create-directory|
|nfs|get_directory|dir_path (_string_)|root_path ("_app_" or "_drive_")|https://maidsafe.readme.io/docs/nfs-get-directory|
|nfs|rename_directory|dir_path (_string_), new_name (_string_)|root_path ("_app_" or "_drive_")|* _Alias to update_directory_|
|nfs|update_directory|dir_path (_string_)|root_path ("_app_" or "_drive_"), meta (_string_), name (_string_)|https://maidsafe.readme.io/docs/nfs-update-directory|
|nfs|delete_directory|dir_path (_string_)|root_path ("_app_" or "_drive_")|https://maidsafe.readme.io/docs/nfs-create-directory|
|nfs|create_file|file_path (_string_), contents (_string_ \| _binary_)|root_path ("_app_" or "_drive_"), meta (_string_), content_type (_string_)|https://maidsafe.readme.io/docs/nfsfile|
|nfs|get_file|file_path (_string_)|root_path ("_app_" or "_drive_"), offset (_int_), length (_int_), range (eg. "bytes 0-1000")|https://maidsafe.readme.io/docs/nfs-get-file|
|nfs|move_file|||https://api.safedev.org/nfs/file/move-file.html|
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

## TODO
* Improve test suite
* Improve documentation
* Use FFI instead of REST
* Use the same interface (same method names) as [safe_app_nodejs](https://github.com/maidsafe/safe_app_nodejs)
