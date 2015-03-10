module Orocos
    module Log
        class LogMarker
            def self.parse(samples)
                markers = Array.new

                samples.each do |sample|
                    if(sample.class.name != "/logger/Annotations")
                        raise "Wrong annotions type: Expected \/logger\/Annotations but got #{sample.class.name}"
                    end

                    type = if(sample.key =~ /log_marker_(.*)$/)
                               $1.to_sym
                           else
                               sample.key
                           end
                    index, comment = if(sample.value =~ /^<(.*)>;(.*)$/)
                                         i = if $1 && !$1.empty?
                                                $1.to_i
                                             else
                                                 0
                                             end
                                         [i,$2]
                                     else
                                         [nil,sample.value]
                                     end

                    markers << LogMarker.new(sample.time,type,index||-1,comment)
                end
                markers 
            end

            attr_reader :time, :type, :index,:comment
            def initialize(time,type,index,comment)
                @time = time
                @type = type
                @index = index
                @comment = comment
            end
        end
    end
end

