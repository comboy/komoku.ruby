require 'faye/websocket'
require 'rack/content_length'
require 'rack/chunked'
require 'json'

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
            ws = Faye::WebSocket.new(env, ['irc', 'xmpp'], :ping => 0)
            handler = nil
            logger.info [:open, ws.url, ws.version, ws.protocol].pretty_inspect
            #handler = SocketHandler.new ws, env

            ws.onopen = lambda do |event|
              logger.info "========= ONOPEN"
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
              handler.received(json)
            end

            ws.onclose = lambda do |event|
              handler.close
              logger.info [:close_ws, event.code, event.reason].pretty_inspect
              # FIXME call something on ws, we need to kill sender thread and stuff
              #handler.on_close
            end

            ws.rack_response
          else
            # FIXME put something reasonable here
            static.call(env)
          end
        end

        port   = opts[:port] || 7373 # TODO config
        secure = false # ARGV[1] == 'ssl'
        engine = 'puma'

        Faye::WebSocket.load_adapter(engine)

        # copy paste for handling different kind of engines
        # https://github.com/faye/faye-websocket-ruby/blob/master/examples/server.rb

        # Puma version
        events = Puma::Events.new($stdout, $stderr)
        binder = Puma::Binder.new(events)
        binder.parse(["tcp://0.0.0.0:#{port}"], App) # FIXME configurable listen addr
        server = Puma::Server.new(app, events)
        @server = server
        server.binder = binder
        @thread = server.run # join
        true

        # Thin
        #EventMachine.schedule do
          #trap("INT") do
            #EventMachine.stop
            #exit
          #end
        #end

        #EM.run do
          #thin = Rack::Handler.get('thin')
          #thin.run(App, :Port => port) do |server|
            ##server.ssl_options = {
            ##  :private_key_file => 'tmp/key.pem',
            ##  :cert_chain_file  => 'tmp/cert.pem'
            ##}
            ##server.ssl = true
          #end
        #end
      end

    end # WobsocketServer


  end
end

