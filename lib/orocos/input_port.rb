module Orocos
    # This class represents output ports on remote task contexts.
    #
    # They are obtained from TaskContext#port or TaskContext#each_port
    class InputPort < Port
        include InputPortBase

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

