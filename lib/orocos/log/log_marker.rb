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
                               :unknown
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
                    
                    if(index)
                        if [:start,:stop,:abort].include?(type)
                            markers << LogMarker.new(sample.time,type,index,comment)
                        else
                            Log.warn "Syntax Error for LogMarker: key: #{sample.key} value: #{sample.value}"
                        end
                    else
                        if [:abort_all,:stop_all,:event].include?(type)
                            markers << LogMarker.new(sample.time,type,-1,comment)
                        else
                            Log.warn "Syntax Error for LogMarker: key: #{sample.key} value: #{sample.value}"
                        end
                    end
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

