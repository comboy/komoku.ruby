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

        # Fetch data (planned to use for multiple points)
        def fetch
          raise "implement me!"
        end

        # Store value
        def put(key, value)
          raise "implement me!"
        end

        # Return last stored value. Returns [timestamp, value]
        def last(key)
          raise "implement me!"
        end

        # Subscribe to key value changes
        def on_change(key, &block)
          raise "implement me!"
          # TODO perhaps Base should include default implementation that specific storage can overwrite
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

