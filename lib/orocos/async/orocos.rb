module Orocos
    module Log
        class OutputPort
            def to_async(options = Hash.new)
                self.tracked = true
                task.to_async(options).port(name,:type => type).wait
            end

            def to_proxy(options = Hash.new)
                self.tracked = true
                task.to_proxy(options).port(name,:type => type).wait
            end
        end

        class TaskContext
            def to_async(options = Hash.new)
                log_replay.name_service_async.get(basename).wait
            end

            def to_proxy(options = Hash.new)
                log_replay.name_service_async.proxy(name,:use => to_async).wait
            end
        end
    end

    class OutputPort
        def to_async(options = Hash.new)
            task.to_async(options).port(name,:type => type)
        end

        def to_proxy(options = Hash.new)
            task.to_proxy(options).port(name,:type => type)
        end
    end

    class TaskContext
        def to_async(options = Hash.new)
            Orocos::Async.get(name,options)
        end

        def to_proxy(options = Hash.new)
            Orocos::Async.proxy(name,options)
        end
    end
end

