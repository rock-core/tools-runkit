# frozen_string_literal: true

module Orocos
    # This is hardcoded here, as we need it to make sure people don't use
    # MQueues on systems where it is not available
    #
    # The comparison with the actual value from the RTT is done in
    # MQueue.available?
    TRANSPORT_MQ = 2
    Port.transport_names[TRANSPORT_MQ] = "MQueue"

    # Support for the POSIX Message Queues transport in RTT
    module MQueue
        # Returns true if the MQ transport is available on this system (i.e.
        # built in RTT)
        def self.available?
            if @available.nil?
                @available =
                    if !defined?(RTT_TRANSPORT_MQ_ID)
                        false
                    elsif error = MQueue.try_mq_open
                        Orocos.warn "the RTT is built with MQ support, but creating message queues fails with: #{error}"
                        false
                    elsif TRANSPORT_MQ != RTT_TRANSPORT_MQ_ID
                        raise InternalError, "hardcoded value of TRANSPORT_MQ differs from the transport ID from RTT (#{TRANSPORT_MQ} != #{RTT_TRANSPORT_MQ_ID}. Set the value at the top of #{File.expand_path(__FILE__)} to #{RTT_TRANSPORT_MQ_ID} and report to the orocos.rb developers"
                    else
                        true
                    end
            else
                @available
            end
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
            #   {Orocos::OutputPort#max_size} and/or OroGen::Spec::OutputPort#max_size
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
                def auto?
                    false
                end

                def auto=(value)
                    raise ArgumentError, "cannot turn automatic MQ handling. It is either not built into the RTT, or you don't have enough permissions to create message queues (in which case a warning message has been displayed)" if value
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

            ##
            # :method:auto_fallback_to_corba?
            # :call-seq:
            #   Orocos::MQueue.auto_fallback_to_corba? => true or false
            #   Orocos::MQueue.auto_fallback_to_corba = new_value
            #
            # If true (the default), a failed connection that is using MQ will
            # only generate a warning, and a CORBA connection will be created
            # instead.
            #
            # While orocos.rb tries very hard to not create MQ connections if it
            # is not possible, it is hard to predict how much memory all
            # existing MQueues in a system take, which is bounded by per-user
            # limits or even by the amount of available kernel memory.
            #
            # If false, an exception is generated instead.
            attr_predicate :auto_fallback_to_corba?, true
        end
        @auto           = false
        @auto_sizes     = available?
        @validate_sizes = available?
        @warn           = true
        @auto_fallback_to_corba = true

        # Verifies that the given buffer size (in samples) and sample size (in
        # bytes) are below the limits defined in /proc
        #
        # This is used by Port.handle_mq_transport if MQueue.validate_sizes? is
        # true.
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
            true
        end

        # Returns the maximum message queue size, in the number of samples
        def self.msg_max
            return @msg_max unless @msg_max.nil?

            @msg_max = if !File.readable?("/proc/sys/fs/mqueue/msg_max")
                           false
                       else
                           Integer(File.read("/proc/sys/fs/mqueue/msg_max").chomp)
                       end
        end

        # Returns the maximum message size allowed in a message queue, in bytes
        def self.msgsize_max
            return @msgsize_max unless @msgsize_max.nil?

            @msgsize_max = if !File.readable?("/proc/sys/fs/mqueue/msgsize_max")
                               false
                           else
                               Integer(File.read("/proc/sys/fs/mqueue/msgsize_max").chomp)
                           end
        end
    end
end
