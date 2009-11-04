require 'typelib'

module Orocos
    class << self
        attr_reader :registry
    end
    @registry = Typelib::Registry.new

    def self.orocos_target
        if ENV['OROCOS_TARGET']
            ENV['OROCOS_TARGET']
        else
            'gnulinux'
        end
    end

    def self.initialize
        Orocos::CORBA.init
        registry.import File.join(`orogen --base-dir`.chomp, 'orogen', 'orocos.tlb')
    end

    # This method assumes that #add_logger has been called at the end of each
    # static_deployment block.
    def self.log_all_ports(options = Hash.new)
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
end

