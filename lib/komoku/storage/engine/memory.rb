require_relative 'base'

module Komoku
  class Storage
    module Engine
      class Memory < Base
        def initialize(opts = {})
          @values = {}
        end

        def put(key, value, time)
          @values[key] ||= []
          @values[key].push [time.to_i, value]
        end

        def last(key)
          @values[key] && @values[key].last
        end

      end
    end
  end
end
