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

        protected

        def step(name)
          units = {
            'S' => 'second',
            'M' => 'minute',
            'H' => 'hour',
            'd' => 'day',
            'w' => 'week',
            'm' => 'month',
            'y' => 'year'
          }
          spans = {}
          spans['S'] = 1
          spans['M'] = 60  * spans['S']
          spans['H'] = 60  * spans['M']
          spans['d'] = 24  * spans['H']
          spans['w'] = 7   * spans['d']
          spans['m'] = 31  * spans['d']
          spans['y'] = 365 * spans['d']

          unit = name[-1].chr
          count = name[0..-1].to_i

          {unit: units[unit], span: spans[unit]*count, count: count}
        end

      end
    end
  end
end

