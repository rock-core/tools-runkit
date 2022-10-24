# frozen_string_literal: true

module Runkit
    # This class represents output ports on remote task contexts.
    #
    # They are obtained from TaskContext#port or TaskContext#each_port
    class InputPort < Port
        include InputPortBase

        # Whether a {#read} should be considered blocking
        #
        # This is set as soon as at least one connection involving this port is
        # set with the 'pull' option
        attr_predicate :blocking_read?, true

        def initialize(task, name, runkit_type_name, model)
            super
            @blocking_read = false
        end

        # (see PortBase#input?)
        def input?
            true
        end

        # Used by InputPortWriteAccess to determine which class should be used
        # to create the writer
        def self.writer_class
            InputWriter
        end

        def pretty_print(pp) # :nodoc:
            pp.text "in "
            super
        end
    end
end
