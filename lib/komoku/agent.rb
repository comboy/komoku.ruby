require 'eventmachine'
require 'faye/websocket'
require 'json'

module Komoku

  # TODO adding abstraction layer for different kind of connection types will change it quite a bit (API stays)
  # should probably also handle accessing storage directly (running it)
  class Agent

    # Options:
    # * server - server url e.g. ws://127.0.0.1:1234/
    # * scope - prepend all keys names with given "#{scope}__"
    def initialize(opts = {})
      # TODO U4 validate if server url is valid
      @server = opts[:server]
      @scope = opts[:scope]
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
      raise "some connection error" unless state == :connected # TODO some nicer exception + more info 
      @connected = true
    end

    def connected?
      !!@connected
    end

    def put(key, value, time = Time.now)
      # TODO handle time param
      @ws.send({put: {key: scoped_name(key), value: value}}.to_json)
      ret = @messages.pop
      JSON.load(ret) == 'ack' # TODO error handling
    end

    def get(key)
      @ws.send({get: {key: scoped_name(key)}}.to_json)
      ret = @messages.pop
      # TODO check if not error
      # TODO we may need to convert it to proper value type I guess?
      JSON.load(ret)
    end

    # THINK assuming scope also applies to events, this may need some second thought
    def subscribe(event)
      @ws.send({sub: {event: scoped_name(event)}}.to_json)
      ret = @messages.pop
      JSON.load(ret) == 'ack' # TODO error handling
    end

    def publish(event, data = {})
      @ws.send({pub: {event: scoped_name(event), data: data}}.to_json)
    end

    protected

    # prepend key name with scope if there is some scope set
    def scoped_name(name)
      @scope ? "#{@scope}__#{name}" : name
    end
  end
end