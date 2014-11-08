require 'eventmachine'
require 'faye/websocket'

module Komoku

  # TODO adding abstraction layer for different kind of connection types will change it quite a bit (API stays)
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
      !!@connected
    end

    def put(key, value, time = Time.now)
      # TODO handle time param
      @ws.send({put: {key: key, value: value}}.to_json)
      ret = @messages.pop
      JSON.load(ret) == 'ack' # TODO error handling
    end

    def get(key)
      @ws.send({get: {key: key}}.to_json)
      ret = @messages.pop
      # TODO check if not error
      # FIXME we may need to convert it to proper value type I guess?
      JSON.load(ret)
    end
  end
end
