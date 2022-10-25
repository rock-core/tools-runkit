# frozen_string_literal: true

require "runkit/test"
require "runkit/name_services/avahi"

module Runkit
    module NameServices
        describe Avahi do
            before do
                @service = Avahi.new("_runkitrb._tcp")
            end

            def wait_for_publication(name, expected_ior, timeout: 10)
                start = Time.now
                while Time.now - start < timeout
                    ior = nil
                    begin
                        capture_subprocess_io { ior = @service.ior(name) }
                    rescue NotFound
                    end

                    return if ior == expected_ior

                    sleep 0.1
                end

                if ior
                    flunk("resolved #{name}, but it does not match the expected IOR")
                else
                    flunk("cannot resolve #{name}")
                end
            end

            it "allows registering a task explicitely and updates it" do
                task = new_ruby_task_context "runkitrb_test"
                @service.register(task)
                wait_for_publication("runkitrb_test", task.ior)
                assert @service.names.include?(task.name)
                capture_subprocess_io do
                    assert_equal task, @service.get(task.name)
                end

                task.dispose

                # This would be better split into two tests, but the avahi name service
                # as it is does not accept de-registering anything ... avahi then
                # refuses to re-register an existing service (which is a good behaviour)

                task = new_ruby_task_context "runkitrb_test"
                @service.register(task)
                wait_for_publication("runkitrb_test", task.ior)
                assert @service.names.include?(task.name)
                capture_subprocess_io do
                    assert_equal task, @service.get(task.name)
                end
            end
        end
    end
end
