require 'eventmachine'
require 'faye/websocket'
require 'json'
require 'logger'
require_relative 'core'

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

    # Connect to server, blocking
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
            conversation do
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
      end if async?

      state = timeout { @ws_events.pop }
      raise "some connection error" unless state == :connected # TODO some nicer exception + more info 
      @should_be_connected = true
      return true
    end

    def disconnect
      return false unless @connected
      @should_be_connected = false
      @ws.close
      @connection_thread.kill
      @push_thread.kill if @push_thread
      true
    end

    def async?
      !! @async
    end

    def connected?
      !! @connected
    end

    def put(key, value, time = Time.now)
      # TODO if key type is numeric .to_f the value
      # or should it be done by storage? probably storage
      msg = {put: {key: scoped_name(key), value: value, time: time.to_f}}
      if async?
        logger.info "async put :#{key} = #{value} #{@push_queue.empty? ? '' : "(#{@push_queue.size} waiting)"}"
        @push_queue.push msg
        true
      else
        logger.info "sync put :#{key} = #{value}"
        conversation do
          logger.debug "  got lock for #{key} = #{value}"
          send msg
          @messages.pop == 'ack' # TODO error handling
        end
      end
    end

    def get(key)
      logger.info "get :#{key}"
      conversation do
        logger.debug "  lock aquired"
        send({get: {key: scoped_name(key)}})
        # TODO check if not error
        # TODO we may need to convert it to proper value type I guess?
        @messages.pop
      end
    end

    def last(key)
      conversation do
        send({fetch: {key: scoped_name(key), opts: {single: 'last'}}})
        # TODO check if not error
        data = @messages.pop
        return nil unless data
        {time: Time.at(data[0]), value: data[1]}
      end
    end

    def previous(key)
      conversation do
        send({fetch: {key: scoped_name(key), opts: {single: 'previous'}}})
        # TODO check if not error
        data = @messages.pop
        return nil unless data
        {time: Time.at(data[0]), value: data[1]}
      end
    end

    # Subscribe to key value changes.
    # Block will be called with 3 arguments: key, current_value, previous_value
    def on_change(key, &block)
      conversation do
        send({sub: {key: scoped_name(key)}})
        @messages.pop
      end
      @subscriptions[scoped_name(key)] ||= []
      @subscriptions[scoped_name(key)] << block
    end

    # List all keys present in storage
    # Returns hash of keys with their types e.g. {'foo' => {type: 'numeric'}}
    # Opts:
    # * include - array of additional data to provide, e.g.
    #             keys(include: [:value]) => {'foo' => {type: 'numeric', value: 42}}
    def keys(opts = {})
      conversation do
        send({keys: opts})
        # TODO check if not error
        ret = @messages.pop
        ret.merge(ret) {|k,v| symbolize_keys v}
      end
    end

    def fetch(key, opts={})
      conversation do
        opts[:since] = opts[:since].to_f if opts[:since] && opts[:since].kind_of?(Time)
        send({fetch: {key: key, opts: opts}})
        # TODO check if not error
        data = @messages.pop
        data.map {|t, v| [Time.at(t), v] }
      end
    end

    # THINK assuming scope also applies to events, this may need some second thought
    #def subscribe(event)
      #conversation do
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

    protected

    def send(msg)
      raise "no connection" unless connected?
      logger.debug "<= #{msg}"
      @ws.send msg.to_json
    end

    # Acquires connection lock so that we don't get response from some different query accidentaly
    # in case many thread are used
    def conversation
      @conn_lock.synchronize do
        raise "messages are not empty, that's bad [#{@messages.pop}]" unless @messages.empty?
        yield
      end
    end

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
        if @reconnecting
          @reconnecting = false
          logger.info "reconnection successful"
          Thread.new { handle_error("reply subscriptions") { replay_subscriptions }}
        end
      end

      @ws.on :close do |event|
        logger.info "disconnected from server" if connected?
        @connected = false
        @ws_events.push :disconnected
        if @opts[:reconnect] && @should_be_connected
          sleep 0.1 # FIXME this is inside EM
          logger.debug "attempting to reconnect #{@name}"
          @reconnecting = true
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
              Thread.new do handle_error("on change key=#{dp['key']}") do
                blk.call symbolize_keys(dp)
              end end
            end
          end
        else # non-event message
          @messages.push data
        end
      end
    end

    # prepend key name with scope if there is some scope set
    def scoped_name(name)
      return name[1..-1] if name[0].chr == Komoku::Core::SCOPE_SEPARATOR
      @scope ? "#{@scope}#{Komoku::Core::SCOPE_SEPARATOR}#{name}" : name.to_s
    end

    # TODO move to some comomn helpers
    def symbolize_keys(hash)
      hash.inject({}){|result, (key, value)|
        new_key = key.kind_of?(String) ? key.to_sym : key
        new_value = value.kind_of?(Hash) ? symoblize_keys(value) : value
        result[new_key] = new_value
        result
      }
    end

    # after reconnect w e need to subscribe to notified values again
    def replay_subscriptions
      @subscriptions.keys.each do |key|
        logger.info "replying subscription for #{key}"
        conversation do
          send({sub: {key: key}})
          ret = @messages.pop
        end
      end
    end
  end
end
