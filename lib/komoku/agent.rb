require 'eventmachine'
require 'faye/websocket'

module Komoku
  class Agent

    def initialize(opts = {})
      # TODO U4 validate if server url is valid
      @server = opts[:server]
      # TODO choose dataset
    end

    def connect
      return false if connected?
      @ws_events = Queue.new
      @messages = Queue.new
      # TODO U1 handle connection timeout
      # TODO U1 handle connection failure
      # TODO handle disconnection (reconnect)
      # probably some exceptions class for it all?
      # TODO abstract away for connection methods other than websocket
      Thread.new do
        begin
          EM.run do
            @ws = Faye::WebSocket::Client.new(@server)
            @ws.on :open do |event|
              @ws_events.push :connected
            end

            @ws.on :close do |event|
              @ws_events.push :disconnected
            end

            @ws.on :message do |event|
              data = event.data
              @ws_events.push [:message, event]
              @messages.push data
            end
          end # EM
        rescue
          @ws_events.push [:exception, $!]
        end
      end # thread

      state = @ws_events.pop
      pp state # FIXME
      raise "some connection error" unless state == :connected # TODO some nicer exception + more info 
      @connected = true
    end

    def connected?
      @connected == true
    end

    def put
      # TODO
    end

    def get
      # TODO
    end
  end
end
