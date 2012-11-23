module Orocos::Async
    class ObjectBase
        attr_reader :event_loop

        def initialize
            @callbacks = Hash.new{ |hash,key| hash[key] = []}
        end

        def on_error(&block)
            @callbacks[:on_error] << block
        end

        def event(name,*args)
            @callbacks[name].each do |block|
                block.call *args
            end
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
