require 'rake'

name = "rorocos"
ext_dir = "ext/rorocos"
lib_dir = "lib/orocos"
# Use absolute main package directory as starting point, since rake-compiler uses a build directory which depends on the system architecture and ruby version
main_dir = File.join(File.dirname(__FILE__),"..","..")


orocos_target = ENV['OROCOS_TARGET'] || 'gnulinux'
FileUtils.rm_f "CMakeCache.txt"
if !system("cmake", "-DRUBY_PROGRAM_NAME=#{FileUtils::RUBY}", "-DCMAKE_INSTALL_PREFIX=#{File.join(main_dir,lib_dir)}", "-DOROCOS_TARGET=#{orocos_target}", "-DCMAKE_BUILD_TYPE=Debug", File.join(main_dir, ext_dir))
        raise "unable to configure the extension using CMake"
end
     
            
