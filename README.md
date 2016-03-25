# Ruby-Safenet

A Ruby library for accessing the SAFE network

## Installation
```
  $ gem install safenet
```

## Usage

```ruby
require "safenet"

SafeNet.set_app_info({
  name:      "Ruby Demo App",
  version:   "0.0.1",
  vendor:    "Vendor's Name",
  id:        "org.thevendor.demo",
})

SafeNet.create_directory("/mydir", is_private: false)
SafeNet.file("/mydir/index.html", is_private: false)
SafeNet.update_file_content("/mydir/index.html", "Hello world!<br>I'm a webpage :D")
SafeNet.register_service("my-wonderful-app", "www", "/mydir")
SafeNet.get_file("/mydir/index.html")

# Then, open http://www.my-wonderful-app.safenet/
```

*File Upload / Download:*
```ruby
# upload
SafeNet.file("/mydir/dog.jpg")
SafeNet.update_file_content("/mydir/dog.jpg", File.read("/home/daniel/Pictures/dog.jpg"))

# download
File.open("/home/daniel/Pictures/dog-new.jpg", "w") do |file|
  file.write(SafeNet.get_file("/mydir/dog.jpg"))
end
```

*Directory's file list:*
```ruby
SafeNet.get_directory("/mydir")["files"].each do |file|
  puts file["name"]
end
```
