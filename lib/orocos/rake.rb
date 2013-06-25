require 'orogen'
module Orocos
    module Rake
        USE_MQUEUE =
            if ENV['USE_MQUEUE'] == '1'
                puts "MQueue enabled through the USE_MQUEUE environment variable"
                puts "set USE_MQUEUE=0 to disable"
                true
            else
                puts "use of MQueue disabled. Set USE_MQUEUE=1 to enable"
                false
            end
        USE_ROS =
            if ENV['USE_ROS'] == '1'
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
        def self.generate_and_build(src, work_basedir, transports = nil)
            src_dir  = File.dirname(src)
            src_name = File.basename(src_dir)

            FileUtils.mkdir_p work_basedir
            work_dir = File.join(work_basedir, src_name)
            if (ENV['TEST_KEEP_WC'] != "1") || !File.directory?(work_dir)
                FileUtils.rm_rf work_dir
                FileUtils.cp_r  src_dir, work_dir
            end

            prefix   = File.join(work_basedir, "prefix")
            ruby_bin   = RbConfig::CONFIG['RUBY_INSTALL_NAME']
            orogen_bin = File.expand_path('../bin/orogen', Orocos::Generation.base_dir)
            Dir.chdir(work_dir) do
                if !transports
                    transports = %w{corba typelib}
                    if USE_MQUEUE
                        transports << 'mqueue'
                    end
                    if USE_ROS
                        transports << 'ros'
                    end
                end

                if !system(ruby_bin, orogen_bin, '--corba', '--no-rtt-scripting', "--transports=#{transports.join(",")}", File.basename(src))
                    raise "failed to build #{src} in #{work_basedir}"
                end

                if !File.directory? 'build'
                    FileUtils.mkdir 'build'
                end
                Dir.chdir 'build' do
                    if !system 'cmake', "-DCMAKE_INSTALL_PREFIX=#{prefix}", "-DCMAKE_BUILD_TYPE=Debug", ".."
                        raise "failed to configure"
                    elsif !system "make", "install"
                        raise "failed to install"
                    end
                end
            end
            ENV['PKG_CONFIG_PATH'] += ":#{prefix}/lib/pkgconfig"
        end
    end
end

