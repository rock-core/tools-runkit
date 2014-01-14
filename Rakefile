require 'rake'
require './lib/orocos/version'
require 'utilrb/doc/rake'

begin
    require 'hoe'
    namespace 'dist' do
        config = Hoe.spec('orocos.rb') do |p|
            self.developer("Sylvain Joyeux", "sylvain.joyeux@dfki.de")

            self.summary = 'Controlling Orocos modules from Ruby'
            self.description = ""
            self.urls = ["http://doudou.github.com/orocos-rb", "http://github.com/doudou/orocos.rb.git"]
            self.changes = ""

            self.extra_deps <<
                ['utilrb', ">= 1.1"] <<
                ['rake', ">= 0.8"]

            #self.spec.extra_rdoc_files.reject! { |file| file =~ /Make/ }
            #self.spec.extensions << 'ext/extconf.rb'
        end

        Rake.clear_tasks(/dist:(re|clobber_|)docs/)
    end

rescue LoadError
    STDERR.puts "cannot load the Hoe gem. Distribution is disabled"
rescue Exception => e
    if e.message !~ /\.rubyforge/
        STDERR.puts "cannot load the Hoe gem, or Hoe fails. Distribution is disabled"
        STDERR.puts "error message is: #{e.message}"
    end
end

def build_orogen(name, options = Hash.new)
    require './lib/orocos/rake'
    work_dir = File.expand_path(File.join('test', 'working_copy'))
    data_dir = File.expand_path(File.join('test', 'data'))

    Orocos::Rake.generate_and_build File.join(data_dir, name, "#{name}.orogen"), work_dir, options
end

task :default => ["setup:ext", "setup:uic"]

namespace :setup do
    desc "builds Orocos.rb C extension"
    task :ext do
        builddir = File.join('ext', 'build')
        prefix   = File.join(Dir.pwd, 'ext')

        FileUtils.mkdir_p builddir
        orocos_target = ENV['OROCOS_TARGET'] || 'gnulinux'
        Dir.chdir(builddir) do
            FileUtils.rm_f "CMakeCache.txt"
            if !system("cmake", "-DRUBY_PROGRAM_NAME=#{FileUtils::RUBY}", "-DCMAKE_INSTALL_PREFIX=#{prefix}", "-DOROCOS_TARGET=#{orocos_target}", "-DCMAKE_BUILD_TYPE=Debug", "..")
                raise "unable to configure the extension using CMake"
            end

            if !system("make") || !system("make", "install")
                throw "unable to build the extension"
            end
        end
        FileUtils.ln_sf "../ext/rorocos_ext.so", "lib/rorocos_ext.so"
    end

    desc "builds the oroGen modules that are needed by the tests"
    task :orogen_all, [:keep_wc,:transports] do |_, args|
        build_orogen 'process', args
        build_orogen 'simple_sink', args
        build_orogen 'simple_source', args
        build_orogen 'echo', args
        build_orogen 'operations', args
        build_orogen 'configurations', args
        build_orogen 'states', args
        build_orogen 'uncaught', args
        build_orogen 'system', args
    end

    desc "builds the test 'process' module"
    task :orogen_process, [:keep_wc,:transports] do |_, args| build_orogen 'process', args end
    desc "builds the test 'simple_sink' module"
    task :orogen_sink, [:keep_wc,:transports]    do |_, args| build_orogen 'simple_sink', args end
    desc "builds the test 'simple_source' module"
    task :orogen_source, [:keep_wc,:transports]  do |_, args| build_orogen 'simple_source', args end
    desc "builds the test 'echo' module"
    task :orogen_echo, [:keep_wc,:transports]    do |_, args| build_orogen 'echo', args end
    desc "builds the test 'states' module"
    task :orogen_states, [:keep_wc,:transports]    do |_, args| build_orogen 'states', args end
    desc "builds the test 'uncaught' module"
    task :orogen_uncaught, [:keep_wc,:transports]    do |_, args| build_orogen 'uncaught', args end
    desc "builds the test 'system' module"
    task :orogen_system, [:keep_wc,:transports]    do |_, args| build_orogen 'system', args end
    desc "builds the test 'operations' module"
    task :orogen_operations, [:keep_wc,:transports]    do |_, args| build_orogen 'operations', args end
    desc "builds the test 'configurations' module"
    task :orogen_configurations, [:keep_wc,:transports]    do |_, args| build_orogen 'configurations', args end
    desc "builds the test 'ros_test' module"
    task :orogen_ros_test, [:keep_wc,:transports]    do |_, args| build_orogen 'ros_test', args end

    task :test do
        Rake::Task['setup:orogen_all'].invoke(true, nil)
    end

    UIFILES = %w{}
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
desc "remove by-products of setup"
task :clean do
    FileUtils.rm_rf "ext/build"
    FileUtils.rm_rf "ext/rorocos_ext.so"
    FileUtils.rm_rf "lib/rorocos_ext.so"
    FileUtils.rm_rf "test/working_copy"
end
task :test => 'setup:test'

if Utilrb.doc?
    namespace 'doc' do
        Utilrb.doc 'api', :include => ['lib/**/*.rb'],
            :exclude => [],
            :target_dir => 'doc',
            :title => 'orocos.rb'

        # desc 'generate all documentation'
        # task 'all' => 'doc:api'
    end

    task 'redocs' => 'doc:reapi'
    task 'doc' => 'doc:api'
else
    STDERR.puts "WARN: cannot load yard or rdoc , documentation generation disabled"
end

