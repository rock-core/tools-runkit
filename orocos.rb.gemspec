# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'orocos/version'

# For backward compatibility with Hoe
task 'gem' => 'build'

require 'rake/extensiontask'
Rake::ExtensionTask.new('rorocos')

Gem::Specification.new do |s|
    s.name = "orocos.rb"
    s.version = Orocos::VERSION
    s.authors = ["Sylvain Joyeux"]
    s.email = "sylvain.joyeux@m4x.org"
    s.summary = "Ruby interface to control Rock components from Ruby"
    s.homepage = "http://rock-robotics.org"
    s.licenses = ["LGPLv2+"]

    s.bindir = 'bin'
    s.require_paths = ["lib"]
    s.extensions = []
    s.extra_rdoc_files = ["README.md"]
    s.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }

    s.add_runtime_dependency "utilrb"
    s.add_development_dependency "rake-compiler"
    s.add_development_dependency "flexmock", ">= 2.0.0"
    s.add_development_dependency "minitest", ">= 5.0", "~> 5.0"
end

