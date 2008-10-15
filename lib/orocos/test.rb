require 'fileutils'

module Orocos
    module Test
        # Generates, builds and installs the orogen component defined by the
        # orogen description file +src+. The compiled package is installed in
        # +prefix+
        def generate_and_build(src, prefix)
            src_dir = File.dirname(src)
            Dir.chdir(src_dir) do
                if !system('orogen', '--corba', src)
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
    end
end

