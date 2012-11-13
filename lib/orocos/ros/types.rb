module Orocos
    module ROS
        class << self
            # [Hash<String,Array<String>>] mappings from ROS message types to
            #   oroGen types. It is filled by Orocos::ROS.load_all_rosmaps,
            #   which is called the first time
            #   Orocos::ROS.find_all_types_for is called
            attr_reader :ros_to_orogen_mappings
            # [Hash<String,String>] mappings from oroGen types to ROS message types.
            #   It is filled by Orocos::ROS.load_all_rosmaps, which is called
            #   the first time Orocos::ROS.find_all_types_for is called
            attr_reader :orogen_to_ros_mappings
        end

        # Loads all known mappings from the oroGen types to the ROS messages.
        # Builds a reverse mapping as well
        def self.load_all_rosmaps
            @ros_to_orogen_mappings = Hash.new
            @orogen_to_ros_mappings = Hash.new
            Orocos.available_typekits.each do |name, pkg|
                rosmap_path = File.join(pkg.prefix, 'share', 'orogen', "#{name}.rosmap")
                if File.file?(rosmap_path)
                    rosmap = Orocos::TypekitMarshallers::ROS.load_rosmap(rosmap_path)
                    orogen_to_ros_mappings.merge! rosmap
                    rosmap.each do |type_name, ros_name|
                        set = (ros_to_orogen_mappings[ros_name] ||= Set.new)
                        set << type_name
                    end
                end
            end
        end

        # Get the list of oroGen types that can be used to communicate with a
        # given ROS message name
        #
        # At first call, it calls load_all_rosmaps to load all the known
        # mappings
        def self.find_all_types_for(message_name)
            if !ROS.ros_to_orogen_mappings
                load_all_rosmaps
            end
            ROS.ros_to_orogen_mappings[message_name] || Set.new
        end

        # Check if a given ROS message type can be accessed on this side
        #
        # At first call, it calls load_all_rosmaps to load all the known
        # mappings
        def self.compatible_message_type?(message_type)
            if !ROS.ros_to_orogen_mappings
                load_all_rosmaps
            end
            ROS.ros_to_orogen_mappings.has_key?(message_type)
        end
    end
end

