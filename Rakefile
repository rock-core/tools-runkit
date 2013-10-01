require 'rake'
require 'rake/extensiontask'
require './lib/orocos/version'

hoe_spec = nil 

begin
    require 'hoe'
    Hoe::plugin :yard

    hoe_spec = Hoe.spec('orocos.rb') do |p|
        self.developer("Sylvain Joyeux", "sylvain.joyeux@dfki.de")

        self.summary = 'Controlling Orocos modules from Ruby'
        self.description = paragraphs_of('README.markdown', 3..5).join("\n\n")
        self.urls = ["http://doudou.github.com/orocos-rb", "http://github.com/doudou/orocos.rb.git"]
        self.changes = ""
        licenses << "GPL v2 or later"

        self.extra_deps <<
            ['utilrb', ">= 1.1"] <<
            ['rake', ">= 0.8"] <<
            ["rake-compiler",   "~> 0.8.0"] <<
            ["hoe-yard",   ">= 0.1.2"]
    end

rescue LoadError
    STDERR.puts "cannot load the Hoe gem. Distribution is disabled"
rescue Exception => e
    if e.message !~ /\.rubyforge/
        STDERR.puts "cannot load the Hoe gem, or Hoe fails. Distribution is disabled"
        STDERR.puts "error message is: #{e.message}"
    end
end

def build_orogen(name)
    require './lib/orocos/rake'
    work_dir = File.expand_path(File.join('test', 'working_copy'))
    prefix   = File.join(work_dir, 'prefix')
    data_dir = File.expand_path(File.join('test', 'data'))

    Orocos::Rake.generate_and_build File.join(data_dir, name, "#{name}.orogen"), work_dir
end


Rake.clear_tasks(/^default$/)
task :default => ["setup:ext", "setup:uic"]

# Leave in top level namespace to allow rake-compiler to build native gem: 'rake native gem'
desc "builds Orocos.rb C extension"
rorocos_task = Rake::ExtensionTask.new('rorocos', hoe_spec.spec) do |ext|
    # Same info as in ext/rocoros/extconf.rb where cmake
    # is used to generate the Makefile
    ext.name = "rorocos"
    ext.ext_dir = "ext/rorocos"
    ext.lib_dir = "lib/orocos"
    ext.tmp_dir = "ext/build"
    ext.gem_spec = hoe_spec.spec
    ext.source_pattern = "*.{c,cpp,cc}"

    if not Dir.exists?(ext.tmp_dir)
        FileUtils.mkdir_p ext.tmp_dir
    end
end

namespace :setup do
    # Rake-compiler provides task: 'compile'
    task :ext => :compile

    desc "builds the oroGen modules that are needed by the tests"
    task :orogen_all do
        build_orogen 'process'
        build_orogen 'simple_sink'
        build_orogen 'simple_source'
        build_orogen 'echo'
        build_orogen 'operations'
        build_orogen 'configurations'
        build_orogen 'states'
        build_orogen 'uncaught'
        build_orogen 'system'
    end

    desc "builds the test 'process' module"
    task :orogen_process do build_orogen 'process' end
    desc "builds the test 'simple_sink' module"
    task :orogen_sink    do build_orogen 'simple_sink' end
    desc "builds the test 'simple_source' module"
    task :orogen_source  do build_orogen 'simple_source' end
    desc "builds the test 'echo' module"
    task :orogen_echo    do build_orogen 'echo' end
    desc "builds the test 'states' module"
    task :orogen_states    do build_orogen 'states' end
    desc "builds the test 'uncaught' module"
    task :orogen_uncaught    do build_orogen 'uncaught' end
    desc "builds the test 'system' module"
    task :orogen_system    do build_orogen 'system' end
    desc "builds the test 'operations' module"
    task :orogen_operations    do build_orogen 'operations' end
    desc "builds the test 'configurations' module"
    task :orogen_configurations    do build_orogen 'configurations' end
    desc "builds the test 'ros_test' module"
    task :orogen_ros_test    do build_orogen 'ros_test' end

    UIFILES = %w{orocos_composer.ui orocos_system_builder.ui}
    desc 'generate all Qt UI files using rbuic4'
    task :uic do
        rbuic = 'rbuic4'
        if File.exists?('/usr/lib/kde4/bin/rbuic4')
            rbuic = '/usr/lib/kde4/bin/rbuic4'
        end

        UIFILES.each do |file|
            file = 'lib/orocos/roby/gui/' + file
            if !system(rbuic, '-o', file.gsub(/\.ui$/, '_ui.rb'), file)
                STDERR.puts "Failed to generate #{file}"
            end
        end
    end
end
task :setup => "setup:ext"

# Add removal of by-products of test setup to the clean task
CLEAN.include("test/working_copy")

