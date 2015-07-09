
module Komoku
  class Server

    class Handler
      # TODO think about args, maybe storage as first arg
      def initialize(opts = {})
        @storage = opts[:storage]
        # Conn must respond to #send
        @conn = opts[:conn]
        @subscriptions = []
      end

      def received(data)
        unless data.kind_of? Hash
          send error: 'Incorrect message'
          return
        end

        # TODO check args
        case data.keys.first

        # => {get: {key: 'foo'}}
        # <= 123
        when 'get'
          # TODO helper for wrapping everything like that
          # FIXME API CHANGE - we cannot just be returning values directly, because string would be not recognizable from 'err'
          begin
            x = @storage.get data['get']['key']
            # TODO agent will need to fetch keys and deserialize this properly i.e. create bigdecimal from string if apropriate
            send x
          rescue
            send 'err'
          end

        # => {put: {key: 'foo', value: 'blah'}}
        # <= 'ack'
        when 'put'
          time = data['put']['time'] ? Time.at(data['put']['time']) : Time.now
          @storage.put data['put']['key'], data['put']['value'], time
          send 'ack'

        when 'keys'
          send @storage.keys(symbolize_keys(data['keys']))

        when 'fetch'
          # somebody killed a kitten somewhere because of the line below FIXME
          data['fetch']['opts']['since'] = Time.at(data['fetch']['opts']['since']) if data['fetch']['opts'] && data['fetch']['opts']['since'] && data['fetch']['opts']['since'].kind_of?(Float)
          send @storage.fetch data['fetch']['key'], symbolize_keys(data['fetch']['opts'])

        when 'stats'
          send(@storage.stats)

        # => {sub: {event: 'foo'}}
        # <= 'ack'
        when 'sub'
          s = data['sub']
          if s['key']
            @subscriptions << @storage.on_change(s['key']) do |change|
              send({pub: change})
            end
          elsif s['event']
            # TODO subscribe to event
          else
            send 'err' # no key or event
          end
          send 'ack'
        # => {define: {foo: {type: 'numeric}}}
        # <= 'ack' # FIXME should be more detailed and per key
        when 'define'
          #TODO filter opts to include only valid ones and err otherwise
          data['define'].each_pair do |key, opts|
            @storage.define_key key, symbolize_keys(opts)
          end
          # TODO error handling, better response
          send 'ack'
        else
          send 'err' # TODO better error handling
        # TODO unsubscribe method
        end
      rescue Exception => e
        send 'err' # FIXME sane exception handling, we need some details and stuff
        raise e
      end

      # TODO Serialization should probablyhappen in WebsocketServer or other type of server
      def send(data)
        @conn.send serialize data
      end

      def close
        @subscriptions.each do |sub|
          @storage.unsubscribe sub
        end
        true
      end

      protected

      def serialize(obj)
        convert_time_to_f(obj).to_json
      end

      def convert_time_to_f(obj)
        if obj.kind_of? Array
          obj.map{|x| convert_time_to_f x}
        elsif obj.kind_of? Hash
          Hash[ *obj.map{|k,v| [k, convert_time_to_f(v)]}.flatten(1) ]
        elsif obj.kind_of? Time
          obj.to_f
        else
          obj
        end
      end

      # TODO move to some comomn helpers
      def symbolize_keys(hash)
        hash.inject({}){|result, (key, value)|
          new_key = key.kind_of?(String) ? key.to_sym : key
          new_value = value.kind_of?(Hash) ? symoblize_keys(value) : value
          result[new_key] = new_value
          result
        }
      end
    end # Handler

  end
end
