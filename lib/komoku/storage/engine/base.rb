module Komoku
  class Storage
    module Engine
      class Base
        def initialize(opts = {})
        end

        # Store value
        def put(key, value)
          raise "implement me!"
        end

        # Return last stored value. Returns [timestamp, value]
        def last(key)
          raise "implement me!"
        end

        # Return last stored value.
        def get(key)
          last = last(key)
          last && last[1]
        end

      end
    end
  end
end

