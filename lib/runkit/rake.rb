# frozen_string_literal: true

require "orogen"
module Runkit
    module Rake
        USE_MQUEUE =
            if ENV["USE_MQUEUE"] == "1"
                puts "MQueue enabled through the USE_MQUEUE environment variable"
                puts "set USE_MQUEUE=0 to disable"
                true
            else
                puts "use of MQueue disabled. Set USE_MQUEUE=1 to enable"
                false
            end
    end
end
