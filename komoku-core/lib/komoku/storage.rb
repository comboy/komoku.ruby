require_relative 'storage/engine'

module Komoku
  class Storage
    def initialize(opts={})
      # use seqlite in memory engine if nothing is provided
      @engine = opts[:engine] || Komoku::Storage::Engine::Database.new(db: Sequel.sqlite)
    end

    def put(key, value, time = Time.now)
      # TODO key name validation
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

    # FIXME rename maybe integarte into #fetch
    def fetch_timespans(key, opts={})
      @engine.fetch_timespans(key, opts)
    end

    # Define key
    def create_key(key, key_type, opts={})
      # TODO key name validation
      @engine.create_key key.to_s, key_type, opts
    end

    # Remove all data associated with given key
    def destroy_key(key)
      @engine.destroy_key key.to_s
    end

    # TODO THINK should implementation of events be here or specific engine?
    def on_change(key, &block)
      @engine.on_change(key.to_s, &block)
    end

    # TODO same as on_change
    def unsubscribe(subscription)
      @engine.unsubscribe(subscription)
    end

    # List all stored keys as a hash
    # TODO we probably would normally only want those used within some latest timespan?
    def keys(opts = {})
      keys_hash = @engine.keys(opts)
      if opts[:include] && opts[:include].map(&:to_sym).include?(:value)
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

    # export all stored data
    def export(opts = {})
      # TODO FIXME ignoring datasets completely
      if opts[:key] # single key data
        @engine.all opts[:key]
      else # all keys
        {
          keys: keys,
          data: Hash[* keys.map {|key,value| [key, export(key: key)]}.flatten(1) ]
        }
      end
    end

    # import data exported with #export
    def import(data)
      # TODO FIXME ignoring datasets completely
      # TODO symbolize keys or just add #export_to_json #import_from_json
      data[:keys].each_pair do |key, kopts|
        @engine.create_key key, kopts[:type]
      end

      data[:data].each_pair do |key, values|
        values.each do |time, value|
          @engine.put key, value, time
        end
      end

      true
    end

  end
end
