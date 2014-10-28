
module Komoku
  class Server

    class Handler
      # TODO think about args, maybe storage as first arg
      def initialize(opts = {})
        @storage = opts[:storage]
        # Conn must respond to #send
        @conn = opts[:conn]
      end

      def received(data)
        puts "HANDLER GOT: #{data}"
        unless data.kind_of? Hash
          send error: 'Incorrect message'
          return
        end

        # TODO check args
        case data.keys.first

        # => {get: {key: 'foo'}}
        # <= 123
        when 'get'
          x = @storage.get data['get']
          # TODO agent will need to fetch keys and deserialize this properly i.e. create bigdecimal from string if apropriate
          send x

        # => {put: {key: 'foo', value: 'blah'}}
        # <= 'ack'
        when 'put'
          # TODO check args
          @storage.put data['put']['key'], data['put']['value']
          send 'ack'
        end
      end

      def send(data)
        @conn.send data.to_json # FIXME serialization must happen in adapter
      end
    end # Handler

  end
end
