# frozen_string_literal: true

require "rake"

ext_dir = "ext/rtt-corba-ext"
lib_dir = "lib/runkit/rtt"

# Use absolute main package directory as starting point, since rake-compiler
# uses a build directory which depends on the system architecture and ruby
# version
main_dir = File.join(File.dirname(__FILE__), "..", "..")
if prefix = ENV["RUBY_CMAKE_INSTALL_PREFIX"]
    archdir = RbConfig::CONFIG["archdir"].gsub(%r{/usr}, "")

    prefix = File.join(prefix, archdir, "runkit")
    prefix = File.absolute_path(File.join(main_dir, prefix))
else
    prefix = File.join(main_dir, lib_dir, "runkit")
end

orocos_target = ENV["OROCOS_TARGET"] || "gnulinux"
FileUtils.rm_f "CMakeCache.txt"

unless system("which cmake")
    raise "cmake command is not available -- make sure cmake is properly installed"
end

cmake_successful = system(
    "cmake", "-DRUBY_PROGRAM_NAME=#{FileUtils::RUBY}",
    "-DCMAKE_INSTALL_PREFIX=#{prefix}", "-DOROCOS_TARGET=#{orocos_target}",
    "-DCMAKE_BUILD_TYPE=Debug", File.join(main_dir, ext_dir)
)
raise "unable to configure the extension using CMake" unless cmake_successful
