require 'komoku/storage/engine'

module Komoku
  class Storage
    def initialize(opts={})
      @engine = Engine::Memory.new
    end

    def put(key, value)
      @engine.put key,value
      # TODO cache
    end

    def get(key)
      # TODO cache
      @engine.get key
    end

  end
end
