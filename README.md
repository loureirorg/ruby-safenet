# Ruby-Safenet

A Ruby library for accessing the SAFE network

## Installation

  $ gem install safenet

## Usage

```ruby
require "safenet"

SafeNet.set_app_info({
  name:      "Demo App",
  version:   "0.0.1",
  vendor:    "maidsafe",
  id:        "org.maidsafe.demo",
})

SafeNet.create_directory("/mydir")
SafeNet.file("/mydir/index.html")
SafeNet.update_file_content("/mydir/index.html", "Hello world!<br>I'm a webpage :D")
SafeNet.register_service("mywonderfulapp", "www", "/mydir")
SafeNet.get_file("/mydir/index.html")
```
