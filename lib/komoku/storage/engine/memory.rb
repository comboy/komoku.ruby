require 'komoku/storage/engine/base'

module Komoku
  class Storage
    module Engine
      class Memory < Base
        def initialize(opts = {})
          @values = {}
        end

        def put(key, value)
          @values[key] ||= []
          @values[key].push [Time.now.to_i, value]
        end

        def last(key)
          @values[key] && @values[key].last
        end

      end
    end
  end
end
