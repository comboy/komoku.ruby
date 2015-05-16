require 'sequel'
require 'sqlite3'
require 'pg'
require 'logger'
require 'time'

module Komoku
  class Storage
    module Engine
      class Database < Base
        def initialize(opts = {})
          # FIXME custom db types
          # FIXME URI from opts
          @db = opts[:db] || Sequel.connect("sqlite://tmp/test.db")
          #@db.loggers << Logger.new(STDOUT)
          prepare_database
          @change_notifications = {}
          @keys_cache = {}
          super
        end

        # Whole thing is a mess for now, did not decide the api yet
        # Movi it to some separet subclass since it's gonna grow
        # opts:
        # * :step - desired resolution of fetched data e.g. 1S, 5M, 1h, 1d
        # * :since
        # * :until
        # * :format - 'timespans'
        # TODO add some check if not too many points are returned (since / span)
        # unless some explicit option (num of points) is provided
        def fetch(name, opts = {})
          return [] unless key = get_key(name)
          return fetch_timespans(key, opts) if opts[:as] == 'timespans'
          return fetch_bool(key, opts) if key[:type] == 'boolean'

          # TODO API inconsistent return format again:
          return last(name) if opts[:single] == 'last'
          return previous(name) if opts[:single] == 'previous'

          # below only numeric type
          scope = @db[:numeric_data_points].where(key_id: key[:id])
          scope = scope.where('time > :since', since: opts[:since]) if opts[:since]
          scope = scope.where('time < :until', until: opts[:until]) if opts[:until]

          if opts[:step]
            s = step opts[:step] # see Engine::Base#step
            # TODO use date_trunc for pg (main use case)
            if @db.adapter_scheme == :postgres
              f_time = "floor((extract(epoch from time::timestamp with time zone)/#{s[:span]}))*#{s[:span]}"
              scope = scope.select(Sequel.lit "to_timestamp(#{f_time}) AS time").group(Sequel.lit f_time).select_append { avg(value_avg).as(value_avg) }
            else # sqlite
              f_time = "(strftime('%s',time)/#{s[:span]})*#{s[:span]}"
              scope = scope.select(Sequel.lit "datetime(#{f_time}, 'unixepoch') AS time").group(Sequel.lit f_time).select_append { avg(value_avg).as(value_avg) }
            end
          end

          scope = scope.order(Sequel.desc(:time)).limit(100) # TODO limit option and order, these are defaults for testing
          #puts "SQL: #{scope.sql}"
          rows = scope.all
          rows.reverse.map do |r|
            [time_wrap(r[:time]), r[:value_avg]]
          end
        end

        # Boolean works like this, if you have true at time A and false at point B, then it is assumed
        # that value was true until B. Fetch should return percentage of time with true for each step
        def fetch_bool(key, opts = {})
          # TODO only handling with :since param
          scope = @db[:boolean_data_points].where(key_id: key[:id])
          scope = scope.where('time > :since', since: opts[:since]) if opts[:since]

          step_span = opts[:step] ? step(opts[:step])[:span] : guess_step_span(opts)
          # TODO brute force, optimize, aggregate
          rows = scope.order(:time).all

          time_values = []
          t = opts[:since]
          loop do
            t += step_span
            break if t > Time.now
            time_values.push t
          end

          lt = opts[:since] # last time
          cv = nil # current value
          st = 0 # sum true
          i = 0 # rows index
          time_values.map do |t|
            st = 0
            loop do
              row = rows[i]
              break unless row && time_wrap(row[:time]) <= t && time_wrap(row[:time]) > lt
              st += row[:time] - lt if cv == true
              cv = row[:value]
              lt = row[:time]
              i += 1
            end
            st += t - lt if cv == true
            lt = t
            [t, st / step_span.to_f]
          end
        end

        # Fetch boolean values as timespans
        def fetch_timespans(key, opts={})
          raise "only boolean" unless key[:type] == 'boolean' # TODO actually it could work for others, especially strings as state
          #return [] unless key
          # Pretty sad N+1 but it should be fine for this kind of stat, maybe cache some day

          # SINCE only
          since = opts[:since]
          since ||= Time.now - 24*3600

          value = opts.keys.include?(:value) ? opts[:value] : true
          # TODO FIXME it doesn't respect nils, just true false so it's counted wrong

          # we assume we want "true" timespans this should actually be an option TODO
          timespans = []

          scope = @db[:boolean_data_points].where(key_id: key[:id])
          # FIXME ugly ugly ugly

          ct = since
          last = scope.where('time < :ct', ct: ct).order(Sequel.desc(:time)).first
          prev_value = (last && last[:value]) || !value


          loop do
            if prev_value == value
              row = scope.where('time > :ct', ct: ct).where(value: !value).order(Sequel.asc(:time)).first
              unless row
                timespans << [ct, nil]
                break
              end
              timespans << [ct, row[:time]-ct]
              ct = row[:time]
              prev_value = !value
            else
              row = scope.where('time > :ct', ct: ct).where(value: value).order(Sequel.asc(:time)).first
              break unless row
              ct = row[:time]
              prev_value = value
            end
          end

          return timespans
        end

        # TODO handle conflicting names of different data types
        def put(name, value, time)
          last_time, last_value = last(name) # TODO cahe it, cache it hard

          key = get_key name, guess_key_type(value)

          if key[:opts][:same_value_resolution] && last_time && time > last_time
            if last_value == value
              return false if (time - last_time) < key[:opts][:same_value_resolution]
            end
          end

          case key[:type]
          when 'boolean'
            @db[:boolean_data_points].insert(key_id: key[:id], value: value, time: time)
          when 'string'
            @db[:string_data_points].insert(key_id: key[:id], value: value, time: time)
          else
            @db[:numeric_data_points].insert(key_id: key[:id], value_avg: value, time: time, value_count: 1, value_max: value, value_min: value)
          end

          # notify about the change
          if @change_notifications[name] && ( last_time.nil? || (time > last_time) && (last_value != value) )
            notify_change name, [last_time, last_value], [time, value]
          end

          return true
        end

        def last(name)
          # OPTIMIZE caching
          return nil unless key = get_key(name)
          ret = @db[type_table key[:type]].where(key_id: key[:id]).order(Sequel.desc(:id)).first
          # TODO abstract away value wrapping
          ret && [ret[:time], key[:type] == 'numeric' ? ret[:value_avg] : ret[:value]]
        end

        def previous(name)
          return nil unless key = get_key(name)
          curr = last(name)
          return nil unless curr
          if key[:type] == 'numeric'
            ret = @db[type_table key[:type]].where(key_id: key[:id]).where('value_avg <> :curr', curr: curr[1]).where('time <= :curr', curr: curr[0]).order(Sequel.desc(:id)).first
            ret && [ret[:time], key[:type] == 'numeric' ? ret[:value_avg] : ret[:value]]
          else
            raise "todo" #TODO
          end
        end

        # TODO I don't like this name, maybe this can be just part of #fetch
        def all(name)
          return nil unless key = get_key(name)
          @db[type_table key[:type]].where(key_id: key[:id]).order(:time).all.map do |x|
            # FIXME numeric aggregation data gets lost
            [x[:time], key[:type] == 'numeric' ? x[:value_avg] : x[:value]]
          end
        end

        # Return list of all stored keys
        def keys(opts = {})
          # TODO keys are strings, type is symbol, inconsistent
          Hash[* @db[:keys].map{|k| [k[:name], {type: k[:key_type]}]}.flatten]
        end

        def stats
          {
            data_points_count: @db[:numeric_data_points].count,
            change_notifications_count: change_notifications_count
          }
        end

        def on_change(key, &block)
          @change_notifications[key] ||= []
          @change_notifications[key] << block
          [key, block]
        end

        def unsubscribe(subscription)
          key, block = subscription
          !! @change_notifications[key].delete(block)
        end

        def change_notifications_count
          @change_notifications.values.flatten.size
        end

        def destroy_key(name)
          key = get_key name
          return false unless key
          @keys_cache.delete name
          @db[type_table key[:type]].where(key_id: key[:id]).delete # goodbye beautiful data points
          @db[:keys].where(id: key[:id]).delete
          true
        end

        def create_key(name, key_type, opts={})
          # TODO create_key will probably be used by define, so this could be a good place to check
          # type compatibility and possibility of upgrading opts, otherwise throw an exception
          return false if key = get_key(name)
          @db[:keys].insert(name: name, key_type: key_type)
          true
        end

        protected

        # if key_type is provided, it will create key with given name if it doesn't exist yet
        def get_key(name, key_type=nil)
          name = name.to_s
          return @keys_cache[name] if @keys_cache[name]

          #TODO FIXME key opts should be stored with key and configurable when defining it
          opts = { # temp defaults
            # don't add points with the same value as previous one if they time diff < N
            same_value_resolution: 600
          }

          key = @db[:keys].first(name: name)
          if key
            @keys_cache[name] = {id: key[:id], type: key[:key_type]}.merge opts: opts
          else
            return nil unless key_type
            raise "key creation failed" unless create_key(name, key_type)
            get_key name
          end
        end

        # for reasons unknown to me sequel returns string instead of time object for sqlite with our custom select
        def time_wrap(obj)
          obj.kind_of?(String) ? Time.parse(obj) : obj
        end

        def notify_change(key, prev, curr)
          return unless @change_notifications[key]
          prev_time, prev_value = prev
          curr_time, curr_value = curr
          @change_notifications[key].each do |block|
            # TODO rescue exceptions?
            change = {
              key: key, # provide key in case some pattern matching is implmented later e.g. notify on foo__*
              prev: prev_value, # APICHANGE seriously these keys sucks
              curr: curr_value,
              prev_time: prev_time,
              curr_time: curr_time
            }
            block.call(change)
          end
        end

        def type_table(type_name)
          raise "unknown type" unless [:boolean, :numeric, :string].include? type_name.to_sym
          "#{type_name}_data_points".to_sym
        end

        def prepare_database
          @db.create_table?(:datasets) do
            primary_key :id
            column :name, String
          end

          @db.create_table?(:keys) do
            #column :id, :primary_key
            primary_key :id
            column :dataset_id, :integer, index: true
            column :name, String
            column :key_type, String, index: true
          end

          @db.create_table?(:numeric_data_points) do
            primary_key :id
            column :key_id, :integer, index: true
            column :time, :timestamp, index: true
            column :value_avg, :double
            column :value_count, :integer
            column :value_max, :double
            column :value_min, :double
            column :value_step, :integer
          end

          # TODO THINK should we allow nil for boolean values?
          @db.create_table?(:boolean_data_points) do
            primary_key :id
            column :key_id, :integer, index: true
            column :time, :timestamp, index: true
            column :value, :boolean
          end

          # XXX we should probably separet strings within set from 'random' strings (aka log lines)
          @db.create_table?(:string_data_points) do
            primary_key :id
            column :key_id, :integer, index: true
            column :time, :timestamp, index: true
            column :value, :text
          end
        end


      end # Database
    end # Engine
  end # Storage
end # Komoku
