require 'orocos/log/replay'

module Kernel
 # Like instace_eval but allows parameters to be passed.
  def instance_exec(*args, &block)
    mname = "__instance_exec_#{Thread.current.object_id.abs}_#{object_id.abs}"
    Object.class_eval{ define_method(mname, &block) }
    begin
      ret = send(mname, *args)
    ensure
      Object.class_eval{ undef_method(mname) } rescue nil
    end
    ret
  end
end

module Orocos::Log
  class TypeConverter 
    attr_reader :time_from,:new_registry,:name
    SubConverter = Struct.new(:old_type_name,:new_type_name,:block) 

    def initialize(name,time_from,new_registry=Orocos.registry,&block)
      return time_from if time_from.is_a? TypeConverter

      #check parameter
      raise 'Parameter time_from must be of type Time' unless time_from.is_a? Time
      raise 'Parameter new_registry must be of type Typelib::Registry' unless new_registry.is_a? Typelib::Registry

      @name_hash = Hash.new
      @name = name
      @time_from = time_from
      @new_registry = new_registry
      instance_eval(&block)
    end

    def new_name_for type_name
      type_name = type_name.class.name unless type_name.is_a? String
      c = @name_hash[type_name]
      c.new_type_name if c
    end

    def new_sample_for type_name
      name = new_name_for type_name
      @new_registry.get(name).new
    end

    def old_type_names
      @name_hash.keys
    end

    def convert_field_from?(sample)
      @name_hash.each_key do |key|
        sample2 = sample.class.registry.get(key)
        return true if sample.class.contains?(sample2) 
      end
      false
    end

    def convert? type_name
      type_name = type_name.class.name unless type_name.is_a? String
      return @name_hash.has_key? type_name
    end

    def convert(dest,src,src_type_name,caller_obj)
      src_type_name = src.class.name unless src_type_name
      c = @name_hash[src_type_name]
      raise "Cannot convert #{src_type_name}!!!" unless c
      caller_obj.instance_exec(dest,src,&c.block)
    end

    def conversion(old_type_name,new_type_name=nil,&block) 
      new_type_name = old_type_name unless new_type_name
      raise 'Parameter old_type_name must be of type String' unless old_type_name.is_a? String
      raise 'Parameter new_type_name must be of type String' unless new_type_name.is_a? String

      new_registry.get(new_type_name) #typelib is raising an error if not
      @name_hash[old_type_name] = SubConverter.new(old_type_name,new_type_name,block)
    end
  end

  class Converter
    class << self 
      attr_reader :converters
    end
    @converters = Array.new

    attr_accessor :pre_fix, :post_fix

    #method to register custom converters
    #it is allowed to use deep_cast insight the converter to convert subfields
    def self.register(*parameter,&block)
      @converters << TypeConverter.new(*parameter,&block)
      @converters.sort!{|a,b| a.time_from <=> b.time_from}
    end
  
    def initialize
      @converters = Converter.converters.clone
      @current_converter = nil
      @post_fix =".new"
      @pre_fix =""
    end
  
    def register(*parameter,&block)
      @converters << TypeConverter.new(*parameter,&block)
      @converters.sort!{|a,b| a.time_from <=> b.time_from}
    end

    #converts logfiles to a new version 
    #if the last parameter is a Time object 
    #the logfiles are converted to a version which was valid at
    #given time. The current Orocos.registry must have 
    #the same type version !!!
    def convert(*logfiles)
      logfiles.flatten!      

      #check last parameters
      final_registry = nil
      if logfiles.last.is_a? Typelib::Registry
          final_registry = logfiles.pop
      else
        final_registry = Orocos.registry
      end

      @current_registry = final_registry # this has to be removed later
      time_to=Time.now
      if logfiles.last.is_a? Time
          time_to = logfiles.pop
      end

      logfiles.each do |logfile|
        puts "converting #{logfile}"
        file = Pocolog::Logfiles.open(logfile)

        output = Pocolog::Logfiles.create(File.join(File.dirname(logfile),pre_fix+File.basename(logfile,".log")+post_fix))
        file.streams.each do |stream|
            puts " converting stream #{stream.name}"
            stream_output = nil
            index = 1
            stream.samples.each do |lg,rt,sample|
              puts "  #{stream.name}.sample #{index}/#{stream.size}"
              new_sample = convert_type(sample,lg,time_to,final_registry)
              stream_output ||= output.stream(stream.name,new_sample.class,true)
              stream_output.write(lg,rt,new_sample)
              index += 1
            end
        end
        output.close
      end
    end

    def clear
      @converters.clear
    end

    #convertes sample to a new type which was valid at time_to
    #the final_registry must have a compatible version!!!
    def convert_type(sample,time_from,time_to=Time.now,final_registry=Orocos.registry)
      raise 'No time periode is given!!!' unless time_from && time_to
      _converters = @converters.map{|c|(c.time_from>=time_from && c.time_from <= time_to) ? c : nil }
      _converters.compact!
      if !_converters.empty?
        _converters.each_with_index do |c,index|
           puts "     Converter #{c.name}" 
           @current_converter = c
           #update current_registry
           
          new_sample = nil
          if @current_converter.convert?(sample)
            new_sample = @current_converter.new_sample_for sample
          else
            new_sample = @current_registry.get(sample.class.name).new
          end
          deep_cast(new_sample,sample)
          sample = new_sample
        end
      end

      #this is needed to be sure that the version is compatible to the
      #final registry
      if @current_registry != final_registry
        @current_converter = nil
        @current_registry = final_registry
        new_sample = @current_registry.get(sample.class.name).new
        deep_cast(new_sample,sample)
        sample = new_sample
      end
      sample
    end

    #copies a vector
    def copy_vector(to,from)
        if to.respond_to?(:data)
            from.data.to_a.each_with_index do |data,i|
                to.data[i] = data 
            end
        else
            from.data.to_a.each_with_index do |data,i|
                to[i] = data 
            end
        end
    end

    #converts src Typelib::Type int dest Typelib::Type
    #uses converters to convert fields and sub fields which have changed
    def deep_cast(dest,src,*excluded_fields)
        @@message = false if !defined? @@message

        excluded_fields.flatten!

        if !dest.is_a?(Typelib::Type) || !src.is_a?(Typelib::Type)
            raise "Cannot convert #{src.class.name} into #{dest.class.name}. "+
              "Register a converter which does the conversion"
        end

        do_not_cast_self = excluded_fields.include?(:self) ? true : false
        excluded_fields.delete :self if do_not_cast_self

        src_type  = src.class
        dest_type = dest.class

        if @current_converter && @current_converter.convert?(src.class.name) && !do_not_cast_self
            STDERR.puts "convert for #{dest_type}" if @@message
            @current_converter.convert(dest,src,nil,self)
        else
            if(dest_type.casts_to?(src_type) && !do_not_cast_self &&(!@current_converter||!@current_converter.convert_field_from?(src)))
                STDERR.puts "copy for #{dest_type}" #if @@message
                Typelib.copy(dest, src)
            elsif src_type < Typelib::ContainerType
                STDERR.puts "deep cast for #{src_type}" if @@message
                dest.clear
                element_type = dest_type.deference
                src.each do |src_element|
                    dst_element = element_type.new
                    if src_element.is_a? Typelib::Type
                        deep_cast(dst_element, src_element)
                    else
                        dst_element = src_element
                    end
                    dest.insert dst_element
                end
            elsif src_type < Typelib::CompoundType
                STDERR.puts "deep cast2 for #{src_type}" if @@message

                dest_fields = dest_type.get_fields.
                    map { |field_name, _| field_name }.
                    to_set

                src_type.each_field do |field_name, src_field_type|
                    next if excluded_fields.include? field_name
                    next if !dest_fields.include?(field_name)

                    dest_field_type = dest_type[field_name]
                    src_value = src.raw_get_field(field_name)

                    if src_value.is_a? NilClass
                        warn "field #{field_name} has an undefined value"
                        puts src.raw_get_field(field_name)
                        puts src[field_name]
                        next
                    end
                    if src_value.is_a? Typelib::Type 
                        if @current_converter && @current_converter.convert?(src_field_type.name)
                            dest.raw_set_field(field_name,@current_converter.new_sample_for(src_field_type.name))
                        end
                        excluded_fields2 = excluded_fields.map{|field| field.match("#{field_name}\.(.*)");$1}.compact
                        deep_cast(dest.raw_get_field(field_name), src_value,excluded_fields2)
                    else
                        #check if the value has to be converted 
                        if(@current_converter && @current_converter.convert?(src_field_type.name))
                            STDERR.puts "convert2 for #{src_field_type.name}" if @@message
                            #be carefull string, symbol etc are no reference  
                            dest_temp = @current_converter.new_sample_for src_field_type.name
                            dest_temp = @current_converter.convert(dest_temp,src.raw_get_field(field_name),src_field_type.name,self)
                            dest.raw_set_field(field_name,dest_temp)
                        else
                            dest.raw_set_field(field_name,src.raw_get_field(field_name))
                        end
                    end
                end
            else
                raise ArgumentError, "cannot deep cast #{src_type} into #{dest_type}"
            end
        end
        dest
    end
  end
end
