require 'fileutils'
require 'typelib'

module Orocos
    module Test
        attr_reader :processes

        def setup
            @processes = Array.new
            super if defined? super
        end

        def teardown
            processes.each { |p| p.kill }
            processes.clear
            super if defined? super
        end

        # Generates, builds and installs the orogen component defined by the
        # orogen description file +src+. The compiled package is installed in
        # +prefix+
        def self.generate_and_build(src, work_basedir)
            src_dir  = File.dirname(src)
            src_name = File.basename(src_dir)

            FileUtils.mkdir_p work_basedir
            work_dir = File.join(work_basedir, src_name)
            FileUtils.rm_rf work_dir
            FileUtils.cp_r  src_dir, work_dir

            prefix   = File.join(work_basedir, "prefix")
            Dir.chdir(work_dir) do
                if !system('orogen', '--corba', File.basename(src))
                    raise "failed to build"
                end

                if !File.directory? 'build'
                    FileUtils.mkdir 'build'
                end
                Dir.chdir 'build' do
                    if !system 'cmake', "-DCMAKE_INSTALL_PREFIX=#{prefix}", ".."
                        raise "failed to configure"
                    elsif !system "make", "install"
                        raise "failed to install"
                    end
                end
            end
            ENV['PKG_CONFIG_PATH'] += ":#{prefix}/lib/pkgconfig"
        end

        def spawn_and_get(component, task = component)
            begin
                process = Orocos::Process.new component
                process.spawn
                process.wait_running(0.5)
            rescue Exception
                process.kill if process
                raise
            end

            processes << process
            Orocos::TaskContext.get "#{component}.#{task}"
        end
    end

    module Spec
        def setup
            @old_pkg_config = ENV['PKG_CONFIG_PATH'].dup
            ENV['PKG_CONFIG_PATH'] += ":#{File.join(WORK_DIR, "prefix", 'lib', 'pkgconfig')}"
            super
        end
        def teardown
            super
            Orocos.instance_variable_set :@registry, Typelib::Registry.new
            Orocos::CORBA.instance_variable_set :@loaded_toolkits, []
            ENV['PKG_CONFIG_PATH'] = @old_pkg_config
        end

        def cleanup_process(process)
            yield(process)
        ensure
            process.kill if process.alive?
        end

        def do_start_processes(procs, name, *remaining_names, &block)
            cleanup_process(Orocos::Process.new(name)) do |process|
                process.spawn
                procs << process
                if remaining_names.empty?
                    procs.each { |p| p.wait_running(0.5) }
                    yield(*procs)
                else
                    do_start_processes(procs, *remaining_names, &block)
                end
            end
        end

        def start_processes(name, *remaining_names, &block)
            do_start_processes([], name, *remaining_names, &block)
        end
    end
end

