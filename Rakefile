require "bundler/gem_tasks"

module Bundler
  class GemHelper
    def install_gem(built_gem_path = nil, local = false)
      conf_filename = File.join(File.expand_path('..', __FILE__), "conf.json")
      File.open(conf_filename, "w") {}
      File.chmod(0666, conf_filename)

      built_gem_path ||= build_gem
      out, _ = sh_with_code("gem install '#{built_gem_path}'#{" --local" if local}")
      raise "Couldn't install gem, run `gem install #{built_gem_path}' for more detailed output" unless out[/Successfully installed/]
      Bundler.ui.confirm "#{name} (#{version}) installed."
    end
  end
end
