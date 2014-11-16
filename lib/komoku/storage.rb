require 'komoku/storage/engine'

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
    def fetch(key, opts={})
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
    # TODO perhaps we would like to also get info about type & number of stored values?
    def keys
      @engine.keys.sort
    end

    def stats
      common_stats = {
        keys_count: keys.count
      }.merge(@engine.stats || {})
    end

  end
end
