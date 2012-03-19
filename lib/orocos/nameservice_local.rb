require 'pp'
module Nameservice
    class Local < Provider
	class << self
	    attr_reader :registered_tasks
	end
	@registered_tasks = Hash.new

	attr_reader :registered_tasks

	def initialize(options)
	    super
	    @registered_tasks = Hash.new
	end

	def resolve(name)
	    pp name
	    pp @registered_tasks
	    pp Local.registered_tasks
	    @registered_tasks[name] || Local.registered_tasks[name]
	end
    end
end #end Nameservice


