
module Komoku
  class Server

    class Handler

      include Helpers

      # TODO think about args, maybe storage as first arg
      def initialize(opts = {})
        @storage = opts[:storage]
        # Conn must respond to #send
        @conn = opts[:conn]
        @subscriptions = []
      end

      def received(data)
        if data.kind_of? Array
          send data.map {|d| reply_to(d)}
        elsif data.kind_of? Hash
          send reply_to(data)
        else
          send error: 'Incorrect message'
        end
      end

      def reply_to(msg)

        # TODO check args
        case msg.keys.first

        # => {get: {key: 'foo'}}
        # <= 123
        when 'get'
          # TODO helper for wrapping everything like that
          # FIXME API CHANGE - we cannot just be returning values directly, because string would be not recognizable from 'err'
          begin
            x = @storage.get msg['get']['key']
            # TODO agent will need to fetch keys and deserialize this properly i.e. create bigdecimal from string if apropriate
            return x
          rescue
            return 'err'
          end

        # => {put: {key: 'foo', value: 'blah'}}
        # <= 'ack'
        when 'put'
          time = msg['put']['time'] ? Time.at(msg['put']['time']) : Time.now
          @storage.put msg['put']['key'], msg['put']['value'], time
          return 'ack'

        when 'keys'
          return @storage.keys(symbolize_keys(msg['keys']))

        when 'fetch'
          # somebody killed a kitten somewhere because of the line below FIXME
          msg['fetch']['opts']['since'] = Time.at(msg['fetch']['opts']['since']) if msg['fetch']['opts'] && msg['fetch']['opts']['since'] && msg['fetch']['opts']['since'].kind_of?(Float)
          return @storage.fetch msg['fetch']['key'], symbolize_keys(msg['fetch']['opts'])

        when 'stats'
          return @storage.stats

        # => {sub: {event: 'foo'}}
        # <= 'ack'
        when 'sub'
          s = msg['sub']
          if s['key']
            @subscriptions << @storage.on_change(s['key']) do |change|
              send({pub: change})
            end
          elsif s['event']
            # TODO subscribe to event
          else
            return 'err' # no key or event
          end
          return 'ack'
        # => {define: {foo: {type: 'numeric}}}
        # <= 'ack' # FIXME should be more detailed and per key
        when 'define'
          #TODO filter opts to include only valid ones and err otherwise
          msg['define'].each_pair do |key, opts|
            @storage.define_key key, symbolize_keys(opts)
          end
          # TODO error handling, better response
          return 'ack'
        else
          return 'err' # TODO better error handling
        # TODO unsubscribe method
        end
      rescue Exception => e
        return 'err' # FIXME sane exception handling, we need some details and stuff
        # FIXME after switching from send to return this is not called anymore. In case of exception other than JSON parsing it must go to logs FIXME
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

    end # Handler

  end
end
