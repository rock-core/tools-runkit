module URI
    class Orocos < URI::Generic
        class << self
            def from_port(port)
                hash = {:type_name => port.type.name}
                Orocos.new("OROCOS",nil,nil,nil,nil,"/port/#{port.full_name}",nil,to_query(hash),nil)
            end

            def to_query(hash)
                str = ""
                hash.each_pair do |key,value|
                    str += "#{key}=#{value}&"
                end
                str[0,str.size-1]
            end

            def from_query(str)
                uri = str
                hash = Hash.new
                a = str.split("&")
                a << str if a.empty?
                a.each do |val|
                    val =~ /(.*)=(.*)/
                    raise InvalidURIError,uri if !$1 || !$2
                    hash[$1.to_sym] = $2
                end
                hash
            end
        end

        attr_reader :hash,:task_name,:port_name

        def initialize(scheme, userinfo, host, port, registry, path, opaque, query, fragment, parser = DEFAULT_PARSER, arg_check = false)
            super
            @hash = Orocos::from_query(query)
            strings = path.split("/")
            strings.shift
            @klass = strings.shift
            if @klass == "port"
                strings = strings.join("/").split(".")
                @task_name = strings.shift
                @port_name = strings.join(".")
            else
                raise ArgumentError, "no class is encoded in:#{path}" unless klass
            end
        end

        def port_proxy?
            !!port_name
        end

        def task_proxy?
            !!task_name
        end

        def task_proxy
            raise ArgumentError,"URI does not point to a TaskContext" unless task_proxy?
            ::Orocos::Async.name_service.proxy(task_name)
        end

        def port_proxy
            raise ArgumentError,"URI does not point to a Port" unless port_proxy?
            task_proxy.port(port_name,:type_name => @hash[:type_name])
        end
    end
end

URI.scheme_list["OROCOS"] ||= URI::Orocos
