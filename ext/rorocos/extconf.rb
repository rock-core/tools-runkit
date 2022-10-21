# frozen_string_literal: true

require "rake"

name = "rorocos"
ext_dir = "ext/rorocos"
lib_dir = "lib/orocos"
# Use absolute main package directory as starting point, since rake-compiler uses a build directory which depends on the system architecture and ruby version
main_dir = File.join(File.dirname(__FILE__), "..", "..")
if prefix = ENV["RUBY_CMAKE_INSTALL_PREFIX"]
    archdir = RbConfig::CONFIG["archdir"].gsub(/\/usr/, "")

    prefix = File.join(prefix, archdir, "orocos")
    prefix = File.absolute_path(File.join(main_dir, prefix))
else
    prefix = File.join(main_dir, lib_dir, "orocos")
end

orocos_target = ENV["OROCOS_TARGET"] || "gnulinux"
FileUtils.rm_f "CMakeCache.txt"
raise "cmake command is not available -- make sure cmake is properly installed" unless system("which cmake")
raise "unable to configure the extension using CMake" unless system("cmake", "-DRUBY_PROGRAM_NAME=#{FileUtils::RUBY}", "-DCMAKE_INSTALL_PREFIX=#{prefix}", "-DOROCOS_TARGET=#{orocos_target}", "-DCMAKE_BUILD_TYPE=Debug", File.join(main_dir, ext_dir))
