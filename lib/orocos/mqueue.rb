module Orocos
    module MQueue
        # Returns true if the MQ transport is available on this system (i.e.
        # built in RTT)
        def self.available?
            defined?(TRANSPORT_MQ)
        end

        class << self
            ##
            # :method:auto?
            # :call-seq:
            #   Orocos::MQueue.auto? => true or false
            #   Orocos::MQueue.auto = new_value
            #
            # If true, orocos.rb will try to use the MQ transport when
            # * the max sample size on the output port is known. If the port type
            #   contains variable-sized containers, it means that
            #   Orocos::OutputPort#max_size and/or Orocos::Spec::OutputPort#max_size
            #   have been used on resp. the port object or the model that describes
            #   it.
            # * it is known that the two involved tasks are on the same host (this
            #   is possible only if orocos.rb is used to start the processes)
            #
            # It is false by default. Additionally, the Orocos::MQueue.warn?
            # predicate tells if a warning should be used for connections that can't
            # use MQ
            if MQueue.available?
                attr_predicate :auto?, true
            else
                def auto?; false end
                def auto=(value)
                    if value
                        raise ArgumentError, "cannot turn automatic MQ handling as it is not built in the RTT"
                    end
                end
            end

            ##
            # :method:warn?
            # :call-seq:
            #   Orocos::MQueue.warn? => true or false
            #   Orocos::MQueue.warn = new_value
            #
            # Controls whether orocos.rb should issue a warning if auto_use? is
            # true but some connection cannot use the message queues
            #
            # See the documentation of Orocos.auto_use? for the constraints on MQ
            # usage.
            attr_predicate :warn?, true

            ##
            # :method:auto_sizes?
            # :call-seq:
            #   Orocos::MQueue.auto_sizes? => true or false
            #   Orocos::MQueue.auto_sizes = new_value
            #
            # Controls whether orocos.rb should compute the required data size
            # for policies where MQ is used and data_size is 0. Turning it off
            # means that you rely on the component developpers to call
            # setDataSample in their components with a sufficiently big sample.
            #
            # See the documentation of Orocos.auto? for the constraints on MQ
            # usage. Setting this off and automatic MQ usage on is not robust
            # and therefore not recommended.
            attr_predicate :auto_sizes?, true

            ##
            # :method:validate_sizes?
            # :call-seq:
            #   Orocos::MQueue.validate_sizes? => true or false
            #   Orocos::MQueue.validate_sizes = new_value
            #
            # Controls whether orocos.rb should validate the data_size field in
            # the policies that require the use of MQ. If true, verify that this
            # size is compatible with the current operating systems limits, and
            # switch back to CORBA if it is not the case (or if the limits are
            # unknown).
            #
            # See the documentation of Orocos.auto? for the constraints on MQ
            # usage. Setting this off and automatic MQ usage on is not robust
            # and therefore not recommended.
            attr_predicate :validate_sizes?, true
        end
        @auto           = false
        @auto_sizes     = available?
        @validate_sizes = available?
        @warn           = true

        def self.valid_sizes?(buffer_size, data_size)
            if !msg_max || !msgsize_max
                Orocos.warn "the system-level MQ limits msg_max and msgsize_max parameters are unknown on this OS. I am disabling MQ support"
                return false
            end

            if buffer_size > msg_max
                msg = yield if block_given?
                Orocos.warn "#{msg}: required buffer size #{buffer_size} is greater than the maximum that the system allows (#{msg_max}). On linux systems, you can use /proc/sys/fs/mqueue/msg_max to change this limit"
                return false
            end

            if data_size > msgsize_max
                msg = yield if block_given?
                Orocos.warn "#{msg}: required sample size #{data_size} is greater than the maximum that the system allows (#{msgsize_max}). On linux systems, you can use /proc/sys/fs/mqueue/msgsize_max to change this limit"
                return false
            end
            return true
        end

        def self.msg_max
            if !@msg_max.nil?
                return @msg_max
            end

            if !File.readable?('/proc/sys/fs/mqueue/msg_max')
                @msg_max = false
            else
                @msg_max = Integer(File.read('/proc/sys/fs/mqueue/msg_max').chomp)
            end
        end

        def self.msgsize_max
            if !@msgsize_max.nil?
                return @msgsize_max
            end

            if !File.readable?('/proc/sys/fs/mqueue/msgsize_max')
                @msgsize_max = false
            else
                @msgsize_max = Integer(File.read('/proc/sys/fs/mqueue/msgsize_max').chomp)
            end
        end
    end
end

