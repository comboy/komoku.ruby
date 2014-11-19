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
    # * async[true] - if false, #put is synchronus and waiting for ack
    def initialize(opts = {})
      # TODO U4 validate if server url is valid
      @server = opts[:server]
      @scope = opts[:scope]
      @async = opts[:async].nil? ? true : opts[:async]
      @opts = opts
      @subscriptions = {}
      # TODO choose dataset

      # All websocket events (including messages), nice for debugging
      @ws_events = Queue.new # FIXME you only pop once, it will just keep growing

      # Response messages received from the server
      @messages = Queue.new

      # Messages to be pushed to the server in async mode
      @push_queue = Queue.new

      # Since there is no indication in protocl what is response to what we must 
      # always wait for response before sending another thing
      @conn_lock = Mutex.new
    end

    def connect
      return false if connected?
      # TODO U1 handle connection timeout
      # TODO U1 handle connection failure
      # TODO handle disconnection (reconnect)
      # probably some exceptions class for it all?
      # TODO abstract away for connection methods other than websocket
      @connection_thread = Thread.new do
        begin
          EM.run do
            @ws = Faye::WebSocket::Client.new(@server)
            @ws.on :open do |event|
              @connected = true
              @ws_events.push :connected
            end

            @ws.on :close do |event|
              @connected = false
              @ws_events.push :disconnected
              # TODO make reconnect a default option, it will need some fixing in tests
              if false # @opts[:reconnect]
                loop do
                  break unless @should_be_connected
                  sleep 0.1
                  puts "should be connected!"
                  begin
                    Timeout::timeout(1) do
                      # TODO try reconnect
                      break
                    end
                  rescue Timeout::Error
                    puts "....timeout"
                  end
                end
              end
            end

            @ws.on :message do |event|
              data = JSON.load(event.data)
              @ws_events.push [:message, event]
              if data.kind_of?(Hash) && data['pub'] # it's some event, handle separately
                dp = data['pub']
                if dp['key']
                  raise "agent was not subscribed to this key [#{db['key']}]" unless @subscriptions[dp['key']]
                  @subscriptions[dp['key']].each do |blk| # TODO 
                    # TODO THINK should we 'unscope' this key if scope is used?
                    # but then what about subs outside agent scope? should  they be possible?
                    # perhaps scope should be some interface... agent.scope('foo')
                    blk.call(dp['key'], dp['prev'], dp['curr'])
                  end
                end
              else # non-event message
                @messages.push data
              end
            end
          end # EM
        rescue
          @ws_events.push [:exception, $!]
        end
      end # thread

      @push_thread = Thread.new do
        loop do
          (sleep(0.1) && next) unless connected?
          msg = @push_queue.pop
          @conn_lock.synchronize do
            @ws.send msg.to_json
            @messages.pop == 'ack' # error handling
            # handle timeout and exceptions
            # FIXME without rescue loop will DIE
          end
        end
      end

      state = @ws_events.pop
      raise "some connection error" unless state == :connected # TODO some nicer exception + more info 
      @should_be_connected = true
      return true
    end

    def async?
      !! @async
    end

    def connected?
      !! @connected
    end

    def put(key, value, time = Time.now)
      msg = {put: {key: scoped_name(key), value: value, time: time}}
      if async?
        @push_queue.push msg
        true
      else
        @conn_lock.synchronize do
          @ws.send msg.to_json
          @messages.pop == 'ack' # TODO error handling
        end
      end
    end

    def get(key)
      @conn_lock.synchronize do
        @ws.send({get: {key: scoped_name(key)}}.to_json)
        # TODO check if not error
        # TODO we may need to convert it to proper value type I guess?
        @messages.pop
      end
    end

    def on_change(key, &block)
      @ws.send({sub: {key: scoped_name(key)}}.to_json)
      @subscriptions[scoped_name(key)] ||= []
      @subscriptions[scoped_name(key)] << block
    end

    # THINK assuming scope also applies to events, this may need some second thought
    #def subscribe(event)
      #@conn_lock.synchronize do
        #@ws.send({sub: {event: scoped_name(event)}}.to_json)
        #@messages.pop == 'ack' # TODO error handling
      #end
    #end

    #def publish(event, data = {})
      #@ws.send({pub: {event: scoped_name(event), data: data}}.to_json)
    #end

    protected

    # prepend key name with scope if there is some scope set
    def scoped_name(name)
      @scope ? "#{@scope}__#{name}" : name.to_s
    end
  end
end
