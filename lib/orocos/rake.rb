# frozen_string_literal: true

require "orogen"
module Orocos
    module Rake
        USE_MQUEUE =
            if ENV["USE_MQUEUE"] == "1"
                puts "MQueue enabled through the USE_MQUEUE environment variable"
                puts "set USE_MQUEUE=0 to disable"
                true
            else
                puts "use of MQueue disabled. Set USE_MQUEUE=1 to enable"
                false
            end
        USE_ROS =
            if ENV["USE_ROS"] == "1"
                puts "ROS enabled through the USE_ROS environment variable"
                puts "set USE_ROS=0 to disable"
                true
            else
                puts "use of ROS disabled. Set USE_ROS=1 to enable"
                false
            end

        # Generates, builds and installs the orogen component defined by the
        # orogen description file +src+. The compiled package is installed in
        # +prefix+
        def self.generate_and_build(src, work_basedir, options = {})
            require "orogen/gen"
            options = Kernel.validate_options options,
                                              keep_wc: false,
                                              transports: false,
                                              make_options: []
            keep_wc, transports, make_options =
                *options.values_at(:keep_wc, :transports, :make_options)

            unless transports
                transports = %w{corba typelib mqueue}
                transports << "ros" if USE_ROS
            end

            src_dir  = File.dirname(src)
            src_name = File.basename(src_dir)

            FileUtils.mkdir_p work_basedir
            work_dir = File.join(work_basedir, src_name)
            FileUtils.rm_rf work_dir unless keep_wc
            FileUtils.cp_r src_dir, work_dir, preserve: true, remove_destination: true

            redirect_options = {}
            if make_jobserver = make_options.find { |opt| opt =~ /^--jobserver-fds=\d+,\d+$/ }
                make_jobserver =~ /^--jobserver-fds=(\d+),(\d+)$/
                fd0 = $1
                fd1 = $2
                redirect_options[Integer(fd0)] = Integer(fd0)
                redirect_options[Integer(fd1)] = Integer(fd1)
            end

            prefix     = File.join(work_basedir, "prefix")
            ruby_bin   = RbConfig::CONFIG["RUBY_INSTALL_NAME"]
            orogen_bin = File.expand_path("../bin/orogen", Orocos::Generation.base_dir)

            build_dir = File.join(work_dir, "build")
            raise "failed to build #{src} in #{work_basedir}" unless system(ruby_bin, orogen_bin, "--corba", "--no-rtt-scripting", "--import=std", "--transports=#{transports.join(',')}", File.basename(src), chdir: work_dir)

            FileUtils.mkdir build_dir unless File.directory? build_dir

            if !system "cmake", "-DCMAKE_INSTALL_PREFIX=#{prefix}", "-DCMAKE_BUILD_TYPE=Debug", "..", chdir: build_dir
                raise "failed to configure"
            elsif !system "make", "install", *make_options, redirect_options.merge(chdir: build_dir)
                raise "failed to install"
            end

            ENV["PKG_CONFIG_PATH"] += ":#{prefix}/lib/pkgconfig"
        end
    end
end
