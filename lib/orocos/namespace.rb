module Orocos

    # The Namespace mixin provides collection classes with several 
    # methods for namespace handling. 
    module Namespace
        #The Delimator between the namespace and the basename.
        DELIMATOR = "/"

        # Sets the namespace name.
        #
        # @param [String] name the new namespace name
        def namespace=(name)
            Namespace.validate_namespace_name(name)
            @namespace = name
        end

        # Returns the name of the used namespace.
        #
        # @return [String] the used namespace name
        def namespace
            @namespace
        end

        # Maps all given names to this namespace
        # by adding the name of this namespace to the beginning
        # of each given name if name is in none or in a different namespace.
        #
        # @param [String,Array] names the names which shall be mapped
        # @return [String,Array] the mapped names
        def map_to_namespace(names)
            if !namespace
                return names
            end

            ary = Array(names)
            ary.map! do |n|
                _,name = split_name(n)
                "#{namespace}#{DELIMATOR}#{name}"
            end
            if names.is_a? Array
                ary 
            else
                ary.first
            end
        end

        # Checks if the given name is in the 
        # same namespace.
        #
        # @param [String] name the name which shall be checked
        # @return [Boolean]
        def same_namespace?(name)
            ns,_ = split_name(name)
            if(!ns || !namespace || ns == namespace)
               true
            else
               false
            end
        end

        # Checks if the given name is in the 
        # same namespace and raises an ArgumentError if not.
        #
        # @param [String] name the name which shall be checked
        # @return [nil]
        # @raise [ArgumentError]
        def verify_same_namespace(name)
            if !same_namespace?(name)
                ns,_ = split_name(name)
                raise ArgumentError, "namespace '#{namespace}' was expected but got '#{ns}' for name '#{name}'"
            end
        end

        # Returns the basename of the given name.
        #
        # @param [String] name the name
        # @return [String] the name without its namespace
        def basename(name)
            _,name = split_name(name)
            name
        end

        # Splits the given name into its namespace name and basename.
        # 
        # @param [String] name the name which shall be split
        # @return [Array<String, String>] its namespace and basename
        def split_name(name)
            Namespace.split_name name
        end

        # Splits the given name into its namespace name and basename.
        #
        # @param [String] name the name which shall be split
        # @return [Array<String, String>] its namespace and basename
        def self.split_name(name)
            if(nil != (name =~ Regexp.new("^(.*)#{DELIMATOR}(.*)$")))
               [$1, $2]
            else
               [nil, name]
            end
        end

        # Validates that the given name can be used as a namespace name
        #
        # The only constraint so far is that namespace names cannot contain the
        # namespace-to-name separation character {DELIMATOR}
        #
        # @param [String] name the namespace name that should be validated
        # @raise [ArgumentError] if name is not a valid namespace name
        def self.validate_namespace_name(name)
            if name =~ /#{DELIMATOR}/
                raise ArgumentError, "namespace names cannot contain #{DELIMATOR}"
            end
        end
    end
end
