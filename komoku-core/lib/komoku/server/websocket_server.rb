require 'faye/websocket'
require 'rack/content_length'
require 'rack/chunked'
require 'json'
require 'catcher'

module Komoku
  class Server


    # Protocol sketch
    # likely to be redesigned, possibly less verbose?
    #
    # => {event: {key: 'foobar', data: 'moo'}}
    # <=
    #
    # => {put: {key: 'foo', value: 'blah'}}
    # => {subscribe: {key: '*'}}
    #
    # => {get: {key: 'foo'}}
    # <= '233'

    #TODO some abstraction layer for different kind of interfaces (REST and stuff)
    class WebsocketServer

      attr_accessor :logger

      class App
        def self.engine
        end

        def self.log(msg)
          # puts "APP LOG: #{msg}"
        end
      end

      def self.logger
        @logger ||= Logger.new nil
      end

      def self.logger=(logger)
        @logger = logger
      end

      # TODO switch to instance
      # TODO handle case when not started yet
      def self.stop
        @server.stop true
      end

      def self.start(opts = {})
        @storage = opts[:storage] || Storage.new
        app = lambda do |env|
          if Faye::WebSocket.websocket?(env)
            # TODO research ping - when positive it was slowing down some tests by what ping was set to
            ws = Faye::WebSocket.new(env, ['irc', 'xmpp'], :ping => 2)
            handler = nil
            logger.info [:open, ws.url, ws.version, ws.protocol].pretty_inspect
            #handler = SocketHandler.new ws, env

            ws.onopen = lambda do |event|
              handler = Server::Handler.new storage: @storage, conn: ws
              # TODO FIXME authentication
            end

            ws.onmessage = lambda do |event|

              logger.info "<= #{event.data}"
              begin
                json = JSON.load event.data
              rescue
                ws.send({err: 'Parsing JSON failed'})
              end
              Catcher.block("handle event") { handler.received(json) }
            end

            ws.onclose = lambda do |event|
              handler.close
              logger.info [:close_ws, event.code, event.reason].pretty_inspect
            end

            ws.rack_response
          else
            # FIXME put something reasonable here
            static.call(env)
          end
        end

        port   = opts[:port] || 7373 # TODO config
        secure = !!opts[:ssl] #false # ARGV[1] == 'ssl'
        engine = opts[:adapter] || 'puma'

        Faye::WebSocket.load_adapter(engine)

        # copy paste for handling different kind of engines
        # https://github.com/faye/faye-websocket-ruby/blob/master/examples/server.rb

        case engine

        when 'puma'

          # Puma version
          events = Puma::Events.new($stdout, $stderr)
          binder = Puma::Binder.new(events)
          binder.parse(["tcp://0.0.0.0:#{port}"], App) # FIXME configurable listen addr
          #binder.parse(["ssl://0.0.0.0:#{port}?key=/comboy/projects/komoku/komoku-core/tmp/ssl/server.key&cert=/comboy/projects/komoku/komoku-core/tmp/ssl/server.crt"], App) # FIXME configurable listen addr
          server = Puma::Server.new(app, events)
          @server = server
          server.binder = binder
          @thread = server.run # join
          true

        when 'thin'

        # Thin
          EventMachine.schedule do
            trap("INT") do
              EventMachine.stop
              exit
            end
          end

          @thread = Thread.new do
            EM.run do
              thin = Rack::Handler.get('thin')
              thin.run(app, :Port => port) do |server|
                if secure
                  server.ssl_options = {
                    :private_key_file => opts[:ssl_key],
                    :cert_chain_file  => opts[:ssl_cert]
                  }
                  server.ssl = true
                end
              end
            end
          end

        else

          raise "unknown adapter"

        end # case
      end #start

    end # WobsocketServer


  end
end

