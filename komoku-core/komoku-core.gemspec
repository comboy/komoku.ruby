# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'komoku/core/version'

Gem::Specification.new do |spec|
  spec.name          = "komoku-core"
  spec.version       = Komoku::Core::VERSION
  spec.authors       = ["comboy"]
  spec.email         = ["kacper.ciesla@gmail.com"]
  spec.summary       = %q{Komoku core.}
  spec.description   = %q{Komoku core TODO desc}
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]


  # FIXME most dependencies should be optional
  spec.add_dependency "sequel"
  spec.add_dependency "sqlite3"
  spec.add_dependency "faye-websocket"
  spec.add_dependency "catcher"
  spec.add_dependency "puma" # for websocket
  #spec.add_dependency "thin" # for websocket
  #spec.add_dependency "goliath" # for websocket
  spec.add_dependency "eventmachine" # websocket client
  #spec.add_dependency "msgpack" # websocket client

  spec.add_development_dependency "bundler", "~> 1.6"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "ZenTest"
  spec.add_development_dependency "rspec-autotest"
  spec.add_development_dependency "wirble"
  spec.add_development_dependency "did_you_mean"
end
