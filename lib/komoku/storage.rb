require 'komoku/storage/engine'

module Komoku
  class Storage
    def initialize(opts={})
      @engine = opts[:engine] || Engine::Memory.new
    end

    def put(key, value)
      @engine.put key.to_s, value
      # TODO cache
    end

    def get(key)
      # TODO cache
      @engine.get key.to_s
    end

  end
end
