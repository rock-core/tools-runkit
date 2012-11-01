module Orocos
    module ROS
        def self.available?
            defined? TRANSPORT_ROS
        end
    end

    if ROS.available?
        Port.transport_names[TRANSPORT_ROS] = 'ROS'
    end
end
