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

        # Return previous stored value. Returns [timestamp, value]
        # It returns first *different* previous value.
        def previous(key)
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

        def guess_key_type(value)
          # TODO other types, probably also guess bool for [on,off] [yes,no]?
          if [true, false].include? value
            'boolean'
          elsif !value.to_s.match(/\d+(\.\d+)?/)
            'string'
          else
            'numeric'
          end
        end

        def guess_step_span(opts)
          raise "no guessing without since yet" unless opts[:since] #TODO
          timespan = Time.now - opts[:since]
          timespan / 50.0 # FIXME we want to make steps human friendly 1d -> 1h 1m -> 1d 10M - 30s etc.
        end

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

