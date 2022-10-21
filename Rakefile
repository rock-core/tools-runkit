# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"
require "./lib/orocos/rake"

Rake::TestTask.new("test:core") do |t|
    t.libs << "lib"
    t.libs << "."
    test_files = FileList["test/**/test_*.rb"]
    test_files.exclude "test/standalone/**/*"
    test_files.exclude "test/async/**/*"
    test_files.exclude "test/ros/**/*"
    t.test_files = test_files
    t.warning = false
end

Rake::TestTask.new("test:ros") do |t|
    t.libs << "lib"
    t.libs << "."
    t.test_files = FileList["test/ros/**/test_*.rb"]
    t.warning = false
end

Rake::TestTask.new("test:async") do |t|
    t.libs << "lib"
    t.libs << "."
    t.test_files = FileList["test/async/**/test_*.rb"]
    t.warning = false
end

Rake::TestTask.new("test:standalone") do |t|
    t.libs << "lib"
    t.libs << "."
    t.test_files = FileList["test/standalone/**/test_*.rb"]
    t.warning = false
end

task "test" => ["test:core", "test:async", "test:standalone"]
task "test" => "test:ros" unless Orocos::Rake::USE_ROS

def build_orogen(name, options = {})
    parsed_options = {}
    parsed_options[:keep_wc] =
        if %w[1 true].include?(options[:keep_wc]) then true
        else false
        end
    parsed_options[:transports] = (options[:transports] || "corba typelib mqueue").split(" ")
    if parsed_options[:transports].empty?
        parsed_options[:transports] = nil
    elsif parsed_options[:transports] == "none"
        parsed_options[:transports] = []
    end

    parsed_options[:make_options] = Shellwords.split(options[:make_options] || "")
                                              .map { |opt| opt.gsub(";", ",") }
    work_dir = File.expand_path(File.join("test", "working_copy"))
    data_dir = File.expand_path(File.join("test", "data"))

    Orocos::Rake.generate_and_build \
        File.join(data_dir, name, "#{name}.orogen"),
        work_dir, parsed_options
end

task "default" do
    Rake::Task["clean"].invoke
    Rake::Task["compile"].invoke
end

# Leave in top level namespace to allow rake-compiler to build native gem: 'rake native gem'
require "rake/extensiontask"
desc "builds Orocos.rb C extension"
Rake::ExtensionTask.new('rtt-corba-ext') do |ext|
    # Same info as in ext/rtt-corba-ext/extconf.rb where cmake
    # is used to generate the Makefile
    ext.name = "rtt-corba-ext"
    ext.ext_dir = "ext/rtt-corba-ext"
    ext.lib_dir = "lib/runkit/rtt"
    ext.source_pattern = "*.{c,cpp,cc}"

    if not Dir.exist?(ext.tmp_dir)
        FileUtils.mkdir_p ext.tmp_dir
    end
end

require "yard/rake/yardoc_task"
YARD::Rake::YardocTask.new

task doc: :yard
task docs: :yard
task redoc: :yard
task redocs: :yard
