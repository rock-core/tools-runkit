require 'rorocos_ext'
require 'typelib'
module Orocos
    class << self
        attr_reader :registry
    end
    @registry = Typelib::Registry.new
    registry.import File.join(`orogen --base-dir`.chomp, 'orogen', 'orocos.tlb')

    # This method assumes that #add_logger has been called at the end of each
    # static_deployment block.
    def self.log_all_ports(options)
        exclude_ports = options[:exclude_ports]
        exclude_types = options[:exclude_types]

        each_process do |process|
            begin
                logger = process.task 'Logger'
                report = logger.rtt_method 'reportPort'

                process.each_task do |task|
                    next if task == logger
                    task.each_port do |port|
                        next unless port.kind_of?(OutputPort)
                        next if exclude_ports && exclude_ports === port.name
                        next if exclude_types && exclude_types === port.type.name
                        Orocos.info "logging % 50s of type %s" % ["#{task.name}:#{port.name}", port.type.name]
                        report.call task.name, port.name
                    end
                end
                logger.file = "#{process.name}.log"
                logger.start

            rescue Orocos::NotFound
                puts "WARN: no logger defined on #{process.name}"
            end
        end
    end

    def self.each_task
        each_process do |p|
            p.task_names.each do |name|
                yield(p.task(name))
            end
        end
    end
    def self.each_process
        ObjectSpace.each_object(Orocos::Process) do |p|
            yield(p)
        end
    end

    # All processes started in the provided block will be automatically killed
    def self.guard
        yield
    ensure
        tasks = ObjectSpace.enum_for(:each_object, Orocos::TaskContext)
        tasks.each do |t|
            if t.process && t.process.running?
                begin
                    t.stop
                rescue
                end
            end
        end

        processes = ObjectSpace.enum_for(:each_object, Orocos::Process)
        processes.each { |mod| mod.kill if mod.running? }
        processes.each { |mod| mod.join if mod.running? }
    end

    module CORBA
        extend Logger::Forward
        extend Logger::Hierarchy

        def self.cleanup
            names = Orocos.task_names.dup
            names.each do |n|
                begin
                    CORBA.info "trying task context #{n}"
                    TaskContext.get(n)
                rescue Orocos::NotFound
                    CORBA.warn "unregistered dangling CORBA name #{n}"
                end
            end
        end

        class << self
            attr_reader :call_timeout
            def call_timeout=(value)
                do_call_timeout(value)
                @call_timeout = value
            end

            attr_reader :connect_timeout
            def connect_timeout=(value)
                do_connect_timeout(value)
                @connect_timeout = value
            end

            attr_reader :loaded_toolkits
            def loaded_toolkit?(name)
                loaded_toolkits.include?(name)
            end
        end
        @loaded_toolkits = []

        if !init
            raise "cannot initialize the CORBA layer"
        end

        call_timeout    = 1000
        connect_timeout = 1000

        def self.orocos_target
            if ENV['OROCOS_TARGET']
                ENV['OROCOS_TARGET']
            else
                'gnulinux'
            end
        end

        def self.load_toolkit(name)
            return if loaded_toolkit?(name)

            pkg = begin
                      Utilrb::PkgConfig.new("#{name}-toolkit-#{orocos_target}")
                  rescue Utilrb::PkgConfig::NotFound
                      raise NotFound, "the '#{name}' toolkit is not available to pkgconfig"
                  end

            libname = "lib#{name}-toolkit-#{orocos_target}.so"
            libpath = pkg.library_dirs.find do |dir|
                full_path = File.join(dir, libname)
                break(full_path) if File.file?(full_path)
            end

            if !libpath
                raise NotFound, "cannot find toolkit shared library for #{name} (searched for #{libname} in #{pkg.libdirs.join(", ")})"
            end

            lib = Typelib::Library.open(libpath, nil, false)
            factory = lib.find('loadRTTPlugin').
                with_arguments('void*')
            factory[nil]

            @loaded_toolkits << name

            # Now, if this is an orogen toolkit, then load the corresponding
            # data types. orogen defines a type_registry field in the pkg-config
            # file for that purpose.
            tlb = pkg.type_registry
            if tlb
                Orocos.registry.import(tlb)
            end

            nil
        end

        def self.refine_exceptions(obj0, obj1 = nil)
            yield

        rescue ComError
            if !obj1
                raise ComError, "communication failed with #{obj0}"
            else
                raise ComError, "communication failed with either #{obj0} or #{obj1}"
            end
        end
    end
end

