require_relative 'storage/engine'

module Komoku
  class Storage
    def initialize(opts={})
      # use seqlite in memory engine if nothing is provided
      @engine = opts[:engine] || Komoku::Storage::Engine::Database.new(db: Sequel.sqlite)
    end

    def put(key, value, time = Time.now)
      @engine.put key.to_s, value, time
      # TODO cache
    end

    # Returns last value of the key
    def get(key)
      # TODO cache
      @engine.get key.to_s
    end

    # TODO FIXME total mess
    def fetch(key, opts={}, more_opts={})
      # fetch :foo, :last_24h
      # fetch :foo, :last_24h, resolution: '1m'
      if opts.kind_of?(Symbol) || opts.kind_of?(String)
        preset = opts.to_sym
        case preset
        when :last_24h
          opts = {since: (Time.now - 24*60)}
        end
      end

      o = {}
      o[:since] = opts[:since] if opts[:since]
      o = opts # FIXME do some validation on l imits max points and magic
      @engine.fetch(key, o.merge(limit: 100))
    end

    # TODO THINK should implementation of events be here or specific engine?
    def on_change(key, &block)
      @engine.on_change(key.to_s, &block)
    end

    # TODO same as on_change
    def unsubscribe(subscription)
      @engine.unsubscribe(subscription)
    end

    # List all stored keys
    # TODO we probably would normally only want those used within some latest timespan?
    def keys(opts = {})
      keys_hash = @engine.keys(opts)
      if opts[:include] && opts[:include].include?(:value)
        # TODO N+1, fix when we have a method to fetch multiple keys values
        keys_hash.merge!(keys_hash) do |key, data|
          data.merge value: get(key)
        end
      end
      keys_hash
    end

    def stats
      common_stats = {
        keys_count: keys.count
      }.merge(@engine.stats || {})
    end

  end
end
