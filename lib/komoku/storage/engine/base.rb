module Komoku
  class Storage
    module Engine
      class Base
        def initialize(opts = {})
          @datasets = {}
        end

        def dataset(name, opts={})
          @datasets[name] ||= Dataset.new(name, opts)
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

