
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
          # TODO check args
          @storage.put data['put']['key'], data['put']['value']
          send 'ack'

        when 'keys'
          send @storage.keys

        when 'fetch'
          send @storage.fetch data['fetch']['key'], symbolize_keys(data['fetch']['opts'])

        # => {sub: {event: 'foo'}}
        # <= 'ack'
        when 'sub'
          s = data['sub']
          if s['key']
            @subscriptions << @storage.on_change(s['key']) do |key, prev, curr|
              send({pub: {key: key, prev: prev, curr: curr}})
            end
          elsif s['event']
            # TODO subscribe to event
          else
            send 'err' # no key or event
          end
          send 'ack'

        # TODO unsubscribe method
        end
      end

      def send(data)
        @conn.send data.to_json # FIXME serialization must happen in adapter
      end

      def close
      end

      protected

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
