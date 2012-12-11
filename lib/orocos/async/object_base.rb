module Orocos::Async
    class ObjectBase
        attr_reader :event_loop

        def initialize(name)
            @callbacks = Hash.new{ |hash,key| hash[key] = []}
            @name = name
        end

        def on_error(&block)
            @callbacks[:on_error] << block
        end

        def event(name,*args)
            @callbacks[name].each do |block|
                block.call *args
            end
            self
        end

        # waits until object gets reachable raises Orocos::NotFound if the
        # object was not reachable after the given time spawn
        def wait(timeout = 25.0)
            time = Time.now
            @event_loop.wait_for do 
                if timeout && timeout <= Time.now-time
                    raise Orocos::NotFound,"#{name} is not reachable after #{timeout} seconds"
                end
                reachable?
            end
        end

        def name
            @name
        end

        def reachable?
            false
        end

        def reset_callbacks
            @callbacks.clear
        end

        protected
        def __on_error(e)
            event :on_error,e
        end
    end
end
