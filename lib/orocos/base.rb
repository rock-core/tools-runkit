require 'orogen'
require 'typelib'
require 'utilrb/module/attr_predicate'
require 'orogen'

# The Orocos main class
module Orocos
    class InternalError < Exception; end
    class AmbiguousName < RuntimeError; end

    def self.register_pkgconfig_path(path)
    	base_path = caller(1).first.gsub(/:\d+:.*/, '')
	ENV['PKG_CONFIG_PATH'] = "#{File.expand_path(path, File.dirname(base_path))}:#{ENV['PKG_CONFIG_PATH']}"
    end

    # Exception raised when the user tries an operation that requires the
    # component to be generated by oroGen, while the component is not
    class NotOrogenComponent < Exception; end
    
    # Base class for all exceptions related to communication with remote
    # processes
    class ComError < RuntimeError; end

    class << self
        # The Typelib::Registry instance that is the union of all the loaded
        # component's type registries
        attr_reader :registry

        # The master oroGen project through  which all the other oroGen projects
        # are imported
        attr_reader :master_project

        # The main configuration manager object
        attr_reader :conf

        # A set of oroGen files that should be loaded in addition to what can be
        # discovered through pkg-config. Add new ones with
        # #register_orogen_files
        attr_reader :registered_orogen_projects

        # A set of typelist files that should be loaded in addition to what can be
        # discovered through pkg-config. Add new ones with
        # #register_typekit
        attr_reader :registered_typekits

        # The set of orogen projects that are available, as a mapping from a
        # name into the project's orogen description file
        attr_reader :available_projects

        # The set of available deployments, as a mapping from the deployment
        # name into the Utilrb::PkgConfig object that represents it
        attr_reader :available_deployments

        # The set of available deployed task contexts, as a mapping from the
        # deployed task context name into set of all the deployment names of
        # the deployments that have a task with that name
        # @return [Hash<String,String>]
        attr_reader :available_deployed_tasks

        # The set of available task libraries, as a mapping from the task
        # library name into the Utilrb::PkgConfig object that represent it
        attr_reader :available_task_libraries

        # The set of available task models, as a mapping from the model name
        # into the task library name that defines it
        attr_reader :available_task_models

        # The set of available typekits, as a mapping from the typekit name to a
        # PkgConfig object
        attr_reader :available_typekits

        # The set of available types, as a mapping from the type name to a
        # [typekit_name, exported] pair, where +typekit_name+ is the name of the
        # typekit that defines it, and +exported+ is a boolean which is true if
        # the type is registered on the RTT type system and false otherwise.
        attr_reader :available_types

        # If true, the orocos logfile that is being generated by this Ruby
        # process is kept. By default, it gets removed when the ruby process
        # terminates
        attr_predicate :keep_orocos_logfile?

        # The name of the orocos logfile for this Ruby process
        attr_reader :orocos_logfile

        # [RubyTaskContext] the ruby task context that is used to provide a RTT
        # interface to this Ruby process. Among other things, it manages the
        # data readers and writers
        attr_reader :ruby_task
    end
    @use_mq_warning = true
    @keep_orocos_logfile = false
    @additional_orogen_files = Array.new
    @registered_typekits = Hash.new
    @registered_orogen_projects = Hash.new

    def self.max_sizes_for(type)
        Orocos.master_project.max_sizes[type.name]
    end

    def self.max_sizes(*args)
        Orocos.master_project.max_sizes(*args)
    end

    # True if there is a typekit named +name+ on the file system
    def self.has_typekit?(name)
        pkg, _ = available_projects[name]
        pkg && pkg.type_registry
    end

    def self.orocos_target
        if ENV['OROCOS_TARGET']
            ENV['OROCOS_TARGET']
        else
            'gnulinux'
        end
    end

    # Helper method for initialize
    def self.add_project_from(pkg) # :nodoc:
        project = pkg.project_name
        if project.empty?
            Orocos.warn "#{pkg.name}.pc does not have a project_name field"
        end
        if description = available_projects[project]
            return description
        end

        if pkg.deffile.empty?
            Orocos.warn "#{pkg.name}.pc does not have a deffile field"
        else
            available_projects[pkg.project_name] = [pkg, pkg.deffile]
        end
    end

    class << self
        # The set of extension names seen so far
        #
        # Whenever a new extension is encountered, Orocos.task_model_from_name
        # tries to require 'extension_name/runtime', which might no exist. Once
        # it has done that, it registers the extension name in this set to avoid
        # trying loading it again
        attr_reader :known_orogen_extensions
    end
    @known_orogen_extensions = Set.new

    # Returns the task model object whose name is +name+, or raises
    # Orocos::NotFound if none exists
    def self.task_model_from_name(name)
        tasklib_name = available_task_models[name]
        if !tasklib_name
            raise Orocos::NotFound, "no task model #{name} is registered"
        end

        tasklib = Orocos.master_project.using_task_library(tasklib_name)
        result = tasklib.tasks[name]
        if !result
            raise InternalError, "while looking up model of #{name}: found project #{tasklib_name}, but this project does not actually have a task model called #{name}"
        end

        result.each_extension do |name, ext|
            if !known_orogen_extensions.include?(name)
                begin
                    require "#{name}/runtime"
                rescue LoadError
                end
                known_orogen_extensions << name
            end
        end
        result
    end

    # Returns the deployment model for the given deployment name
    #
    # @return [Orocos::Spec::Deployment] the deployment model
    # @raise [Orocos::NotFound] if no deployment with that name exists
    def self.deployment_model_from_name(name)
        project_name = available_deployments[name]
        if !project_name
            raise Orocos::NotFound, "there is no deployment called #{name}"
        end

        tasklib = Orocos.master_project.using_task_library(project_name.project_name)
        deployment = tasklib.deployers.find { |d| d.name == name }
        if !deployment
            raise InternalError, "cannot find the deployment called #{name} in #{tasklib}. Candidates were #{tasklib.deployers.map(&:name).sort.join(", ")}"
        end
        deployment
    end

    # Returns the deployed task model for the given name
    #
    # @param [String] name the deployed task name
    # @param [String] deployment_name () the name of the deployment in which the
    #   task is defined. It must be given only when more than one deployment
    #   defines a task with the requested name
    # @return [Orocos::Spec::TaskDeployment] the deployed task model
    # @raise [Orocos::NotFound] if no deployed tasks with that name exists
    # @raise [Orocos::NotFound] if deployment_name was given, but the requested
    #   task is not defined in this deployment
    # @raise [Orocos::AmbiguousName] if more than one task exists with that
    #   name. In that case, you will have to provide the deployment name
    #   explicitly using the second argument
    def self.deployed_task_model_from_name(name, deployment_name = nil)
        if deployment_name
            deployment = deployment_model_from_name(deployment_name)
        else
            deployment_names = Orocos.available_deployed_tasks[name]
            if !deployment_names
                raise Orocos::NotFound, "cannot find a deployed task called #{name}"
            elsif deployment_names.size > 1
                raise Orocos::AmbiguousName, "more than one deployment defines a deployed task called #{name}: #{deployment_names.map(&:name).sort.join(", ")}"
            end
            deployment = deployment_model_from_name(deployment_names.first)
        end

        if !(task = deployment.find_task_by_name(name))
            if deployment_name
                raise Orocos::NotFound, "deployment #{deployment_name} does not have a task called #{name}"
            else
                raise InternalError, "deployment #{deployment_name} was supposed to have a task called #{name} but does not"
            end
        end
        task
    end

    # Loads a directory containing configuration files
    #
    # See the documentation of ConfigurationManager#load_dir for more
    # information
    def self.load_config_dir(dir)
        conf.load_dir(dir)
    end

    # Returns true if Orocos.load has been called
    def self.loaded?
        !!@master_project
    end

    def self.load(name = nil)
        if ENV['ORO_LOGFILE'] && orocos_logfile && (ENV['ORO_LOGFILE'] != orocos_logfile)
            raise "trying to change the path to ORO_LOGFILE from #{orocos_logfile} to #{ENV['ORO_LOGFILE']}. This is not supported"
        end
        ENV['ORO_LOGFILE'] ||= File.expand_path("orocos.#{name || 'orocosrb'}-#{::Process.pid}.txt")
        @orocos_logfile = ENV['ORO_LOGFILE']

        if @available_projects && !@available_projects.empty?
            return
        end

        @master_project = Orocos::Generation::Component.new
        @registry = master_project.registry
        @conf = ConfigurationManager.new
        @available_projects ||= Hash.new
        @loaded_typekit_registries.clear
        @loaded_typekit_plugins.clear

        load_standard_typekits

        # Finally, update the set of available projects
        Utilrb::PkgConfig.each_package(/^orogen-project-/) do |pkg_name|
            if !available_projects.has_key?(pkg_name)
                pkg = Utilrb::PkgConfig.new(pkg_name)
                add_project_from(pkg)
            end
        end

        # Load the name of all available task libraries
        if !available_task_libraries
            @available_task_libraries = Hash.new
            Utilrb::PkgConfig.each_package(/-tasks-#{Orocos.orocos_target}$/) do |pkg_name|
                pkg = Utilrb::PkgConfig.new(pkg_name)
                tasklib_name = pkg_name.gsub(/-tasks-#{Orocos.orocos_target}$/, '')

                # Verify that the corresponding orogen project is indeed
                # available. If not, just ignore the library
                if Orocos.available_projects.has_key?(pkg.project_name)
                    available_task_libraries[tasklib_name] = pkg
                else
                    Orocos.warn "found task library #{tasklib_name}, but the corresponding oroGen project #{pkg.project_name} could not be found. Consider deleting #{pkg.path}."
                end
            end
        end


        if !available_deployments
            @available_deployments = Hash.new
            @available_deployed_tasks = Hash.new
            Utilrb::PkgConfig.each_package(/^orogen-\w+$/) do |pkg_name|
                pkg = Utilrb::PkgConfig.new(pkg_name)
                deployment_name = pkg_name.gsub(/^orogen-/, '')

                # Verify that the corresponding orogen project is indeed
                # available. If not, just ignore the library
                if Orocos.available_projects.has_key?(pkg.project_name)
                    available_deployments[deployment_name] = pkg
                    if pkg.deployed_tasks # to ensure a smooth upgrade from older version of oroGen
                        pkg.deployed_tasks.split(',').each do |deployed_task_name|
                            available_deployed_tasks[deployed_task_name] ||= Set.new
                            available_deployed_tasks[deployed_task_name] << deployment_name
                        end
                    end
                else
                    Orocos.warn "found deployment #{deployment_name}, but the corresponding oroGen project #{pkg.project_name} could not be found. Consider deleting #{pkg.path}."
                end
            end
        end

        # Create a class_name => tasklib mapping for all task models available
        # on this sytem
        if !available_task_models
            @available_task_models = Hash.new
            available_task_libraries.each do |tasklib_name, tasklib_pkg|
                tasklib_pkg.task_models.split(",").
                    each { |class_name| available_task_models[class_name] = tasklib_name }
            end
            registered_typekits.each do |name, (tlb, typelist)|
                Orocos.master_project.register_typekit(name, tlb, typelist)
            end
            registered_orogen_projects.each do |name, orogen|
                Orocos.master_project.register_orogen_file(orogen, name)
            end
            # We must now load the projects explicitely, so that we can register
            # the task models as well
            registered_orogen_projects.each_key do |name|
                load_independent_orogen_project(name)
            end
        end

        if !available_typekits
            @available_typekits = Hash.new
            Utilrb::PkgConfig.each_package(/-typekit-#{Orocos.orocos_target}$/) do |pkg_name|
                pkg = Utilrb::PkgConfig.new(pkg_name)
                typekit_name = pkg_name.gsub(/-typekit-#{Orocos.orocos_target}$/, '')

                if Orocos.available_projects.has_key?(pkg.project_name)
                    if Orocos.available_projects[pkg.project_name][0].type_registry
                        available_typekits[typekit_name] = pkg
                    else
                        Orocos.warn "found typekit #{typekit_name}, but the corresponding oroGen project #{pkg.project_name} does not have a typekit. Consider deleting #{pkg.path}."
                    end
                else
                    Orocos.warn "found typekit #{typekit_name}, but the corresponding oroGen project #{pkg.project_name} could not be found. Consider deleting #{pkg.path}."
                end
            end
        end

        if !available_types
            @available_types = Hash.new
            available_typekits.each do |typekit_name, typekit_pkg|
                typelist = typekit_pkg.type_registry.gsub(/tlb$/, 'typelist')
                typelist, typelist_exported =
                    Orocos::Generation::ImportedTypekit.parse_typelist(File.read(typelist))
                typelist = typelist - typelist_exported
                typelist.compact.each do |typename|
                    if existing = @available_types[typename]
                        Orocos.info "#{typename} is defined by both #{existing[0]} and #{typekit_name}"
                    else
                        @available_types[typename] = [typekit_name, false]
                    end
                end
                typelist_exported.compact.each do |typename|
                    if existing = @available_types[typename]
                        Orocos.info "#{typename} is defined by both #{existing[0]} and #{typekit_name}"
                    end
                    @available_types[typename] = [typekit_name, true]
                end
            end
        end
        nil
    end

    def self.clear
        @master_project = nil
        @available_projects.clear if @available_projects
        @ruby_task.dispose if @ruby_task
        if export_types? && registry
            registry.clear_exports(type_export_namespace)
        end
        @registry = nil
    end

    def self.reset
        clear
        load
    end

    # Registers an orogen file, or all oroGen files contained in a directory, to
    # be loaded in Orocos.load
    def self.register_orogen_files(file_or_dir)
        if File.directory?(file_or_dir)
            Dir.glob(File.join(file_or_dir, "*.typelist")) do |file|
                register_orogen_files(file)
            end
            Dir.glob(File.join(file_or_dir, "*.orogen")) do |file|
                register_orogen_files(file)
            end
        elsif File.extname(file_or_dir) == ".typelist"
            name = File.basename(file_or_dir, ".typelist")
            tlb_file = File.join(File.dirname(file_or_dir), "#{name}.tlb")
            if File.file?(tlb_file)
                registered_typekits[name] = [File.read(tlb_file), File.read(file_or_dir)]
            end
        elsif File.extname(file_or_dir) == ".orogen"
            name = File.basename(file_or_dir, ".orogen")
            registered_orogen_projects[name] = File.read(file_or_dir)
        else
            raise ArgumentError, "don't know what to do with #{file_or_dir}"
        end
    end

    # Loads an oroGen file or all oroGen files contained in a directory, and
    # registers them in the available_task_models set.
    def self.load_independent_orogen_project(file)
        tasklib = Orocos.master_project.
            using_task_library(file, :define_dummy_types => true, :validate => false)

        if !tasklib.self_tasks.empty?
            Orocos.available_task_libraries[tasklib.name] = file
        end
        tasklib.self_tasks.each do |task|
            Orocos.available_task_models[task.name] = file
        end

        tasklib.deployers.each do |dep|
            Orocos.master_project.loaded_deployments[dep.name] = dep
        end
        if tasklib.typekit
            Orocos.load_registry(tasklib.typekit.registry, tasklib.name)
        end
    end

    class << self
        attr_predicate :disable_sigchld_handler, true
    end

    # Returns true if Orocos.initialize has been called and completed
    # successfully
    def self.initialized?
        CORBA.initialized?
    end

    # Initialize the Orocos communication layer and load all the oroGen models
    # that are available.
    #
    # This method will verify that the pkg-config environment is sane, as it is
    # demanded by the oroGen deployments. If it is not the case, it will raise
    # a RuntimeError exception whose message will describe the particular
    # problem. See the "Error messages" package in the user's guide for more
    # information on how to fix those.
    def self.initialize(name = "orocosrb_#{::Process.pid}")
        if !registry
            self.load(name)
        end

        # Install the SIGCHLD handler if it has not been disabled
        if !disable_sigchld_handler?
            trap('SIGCHLD') do
                begin
                    while dead = ::Process.wait(-1, ::Process::WNOHANG)
                        if mod = Orocos::Process.from_pid(dead)
                            mod.dead!($?)
                        end
                    end
                rescue Errno::ECHILD
                end
            end
        end

        if !Orocos::CORBA.initialized?
            Orocos::CORBA.initialize
        end
        @initialized = true

        if Orocos::ROS.enabled?
            Orocos::ROS.initialize(name)
        end

        # add default name services
        self.name_service << Orocos::CORBA.name_service
        if defined?(Orocos::Async)
            Orocos.name_service.name_services.each do |ns|
                Orocos::Async.name_service.add(ns)
            end
        end
        @ruby_task = RubyTaskContext.new(name)
    end

    def self.create_orogen_interface(name = nil, &block)
        Orocos::Spec::TaskContext.new(Orocos.master_project, name, &block)
    end
end

at_exit do
    if !Orocos.keep_orocos_logfile? && Orocos.orocos_logfile
        FileUtils.rm_f Orocos.orocos_logfile
    end
end

