require 'eventmachine'
require 'faye/websocket'
require 'json'
require 'logger'

module Komoku

  # TODO adding abstraction layer for different kind of connection types will change it quite a bit (API stays)
  # should probably also handle accessing storage directly (running it)
  class Agent

    DEFAULT_TIMEOUT = 10

    attr_writer :logger

    # Options:
    # * server - server url e.g. ws://127.0.0.1:1234/
    # * scope - prepend all keys names with given "#{scope}."
    # * async[true] - if false, #put is synchronus and waiting for ack
    # * timeout - assume failure if server doesnt respond after this amount of seconds
    def initialize(opts = {})
      # TODO U4 validate if server url is valid
      @server = opts[:server]
      @scope = opts[:scope]
      @async = opts[:async].nil? ? true : opts[:async]
      # TODO make reconnect a default option, it will need some fixing in tests
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
            logger.debug "initializing connection"
            init_connection
          end # EM
        rescue
          @ws_events.push [:exception, $!]
        end
      end # thread

      @push_thread = Thread.new do
        loop do
          (sleep(0.1) && next) unless connected?
          msg = @push_queue.pop
          logger.debug "qsize = #{@push_queue.size} attempting to push msg from queue #{msg}"
          begin
            @conn_lock.synchronize do
              timeout do
                send msg
                @messages.pop == 'ack' # error handling
              end
            end
          rescue
            logger.error "[#{$!}] failed to send #{msg}"
            # FIXME this is messy and needs thinking, cases:
            # * server drops connection, we reconnect and want to push again
            # * server didnt drop connection, it just took > timeout to respond - terrible, we receive ack out of nowhere, perhaps we want to reconnect here?
            @push_queue.push msg # should actually still be at the beginnig of the queue
            # so just in case..
            # TODO instead of reconnecting just in case, we will check if @messages are empty after acquiring lock
            # handle_error('reconnect after failed push') { disconnect; connect }
          end
        end
      end

      state = timeout { @ws_events.pop }
      raise "some connection error" unless state == :connected # TODO some nicer exception + more info 
      @should_be_connected = true
      return true
    end

    def disconnect
      return false unless @connected
      @should_be_connected = false
      @ws.close
      true
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
        logger.info "async put #{key} = #{value}"
        @push_queue.push msg
        true
      else
        logger.info "sync put #{key} = #{value}"
        @conn_lock.synchronize do
          logger.debug "  got lock for #{key} = #{value}"
          send msg
          @messages.pop == 'ack' # TODO error handling
        end
      end
    end

    def get(key)
      logger.info "get :#{key}"
      @conn_lock.synchronize do
        logger.debug "  lock aquired"
        send({get: {key: scoped_name(key)}})
        # TODO check if not error
        # TODO we may need to convert it to proper value type I guess?
        @messages.pop
      end
    end

    def on_change(key, &block)
      send({sub: {key: scoped_name(key)}})
      @subscriptions[scoped_name(key)] ||= []
      @subscriptions[scoped_name(key)] << block
    end

    def keys
      # TODO abstract away conn_lock synchronize and add check if messages are empty, 
      # also messages should probably be called replies
      @conn_lock.synchronize do
        send({keys: {}})
        # TODO check if not error
        @messages.pop
      end
    end

    def fetch(key, opts={})
      @conn_lock.synchronize do
        send({fetch: {key: key, opts: opts}})
        # TODO check if not error
        @messages.pop
      end
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

    def logger
      @logger ||= Logger.new nil
    end

    def send(msg)
      raise "no connection" unless connected?
      logger.debug "<= #{msg}"
      @ws.send msg.to_json
    end

    protected

    def handle_error(msg='')
      begin
        yield
      rescue
        logger.error "ERR [#{$!.to_s}] #{msg}"
      end
    end

    def timeout
      Timeout::timeout(@opts[:timeout] || DEFAULT_TIMEOUT) do
        yield
      end
    end

    def init_connection
      @ws = Faye::WebSocket::Client.new(@server)
      @ws.on :open do |event|
        @connected = true
        @ws_events.push :connected
      end

      @ws.on :close do |event|
        logger.info "disconnected from server" if connected?
        @connected = false
        @ws_events.push :disconnected
        if @opts[:reconnect] && @should_be_connected
          sleep 0.1
          logger.debug "attempting to reconnect"
          init_connection
        end
      end

      @ws.on :message do |event|
        data = JSON.load(event.data)
        @ws_events.push [:message, event]
        logger.debug "=> #{data}"
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
    end

    # prepend key name with scope if there is some scope set
    def scoped_name(name)
      @scope ? "#{@scope}#{Komoku::Core::SCOPE_SEPARATOR}#{name}" : name.to_s
    end
  end
end
