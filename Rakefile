# frozen_string_literal: true

require "rake/testtask"
require_relative "lib/runkit/rake"

Rake::TestTask.new("test:lib") do |t|
    t.libs << "lib"
    t.libs << "."
    t.test_files =
        FileList["test/**/test_*.rb"]
        .exclude("test/name_services/test_avahi.rb")
    t.warning = false
end

task "default" do
    Rake::Task["clean"].invoke
    Rake::Task["compile"].invoke
end

# Leave in top level namespace to allow rake-compiler to build native gem: 'rake native gem'
require "rake/extensiontask"
desc "builds Runkit's extension"
Rake::ExtensionTask.new("rtt_corba_ext") do |ext|
    # Same info as in ext/rtt-corba-ext/extconf.rb where cmake
    # is used to generate the Makefile
    ext.name = "rtt_corba_ext"
    ext.ext_dir = "ext/rtt_corba_ext"
    ext.lib_dir = "lib/runkit"
    ext.source_pattern = "*.{c,cpp,cc}"

    FileUtils.mkdir_p ext.tmp_dir unless Dir.exist?(ext.tmp_dir)
end

require "yard/rake/yardoc_task"
YARD::Rake::YardocTask.new

task doc: :yard
task docs: :yard
task redoc: :yard
task redocs: :yard

require "rubocop/rake_task"
RuboCop::RakeTask.new
task "test" => "rubocop"
task "test" => "test:lib"
