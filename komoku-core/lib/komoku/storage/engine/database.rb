require 'sequel'
require 'sqlite3'
require 'pg'
require 'logger'
require 'time'
require 'json'

module Komoku
  class Storage
    module Engine
      class Database < Base
        include Komoku::Helpers

        def initialize(opts = {})
          # FIXME custom db types
          # FIXME URI from opts
          @db = opts[:db] || Sequel.connect("sqlite://tmp/test.db")
          #@db.loggers << Logger.new(STDOUT)
          prepare_database
          @change_notifications = {}
          @keys_cache = {}

          # For uptime keys, we need to monitor all true values to set them false when they are not updated
          @uptime_checks = {}
          init_uptime_checks

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

          # TODO API inconsistent return format again:
          return last(name) if opts[:single] == 'last'
          return previous(name) if opts[:single] == 'previous'

          return fetch_timespans(key, opts) if opts[:as] == 'timespans'
          return fetch_bool(key, opts) if key[:type] == 'boolean'


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
          is_newest = last_time.nil? || (time > last_time)

          key = get_key name
          # get_key with type provided creates key if it doesn't exist
          # so we hit db two times for put for new key, that sucks but not as much as some other things (low prior)
          key = get_key name, guess_key_type(value) unless key

          bump_uptime(name, key) if key[:type] == 'uptime' && value == true && is_newest # TODO move when we have key type classes

          if key[:opts][:same_value_resolution] && last_time && time > last_time
            if last_value == value
              return false if (time - last_time) < key[:opts][:same_value_resolution]
            end
          end

          values = { key_id: key[:id], value: value, time: time }

          if key[:type] == 'numeric'
            values.delete :value
            values.merge!(value_avg: value, value_count: 1, value_max: value, value_min: value)
          end

          @db[ type_table(key[:type]) ].insert values

          # notify about the change
          # IMPROVE THREADS - with multiple thread last_time may be unreliable and may cause notification not to fire in some rare special case (I guess)
          if @change_notifications[name] && is_newest && (last_value != value)
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
          Hash[* @db[:keys].map do |k|
            info =  { type: k[:key_type] }
            opts = k[:key_opts_json] ? JSON.load(k[:key_opts_json]) : {}
            info.merge!(opts: opts) if opts != {}
            [k[:name], info] # becomes name: info_hash
            end.flatten
          ]
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
          @db[:keys].insert(name: name.to_s, key_type: key_type.to_s, key_opts_json: opts.to_json)
          true
        end

        def update_key(name, key_type, opts={})
          key = get_key(name)
          return false unless key
          raise "cannot update type" unless key_type == key[:type]
          @db[:keys].where(id: key[:id]).update(key_opts_json: opts.to_json)
          true
        end

        def key_opts(name)
          get_key(name)
        end

        protected

        # This is called for uptime key if current value is true
        # We need to automatically set false in case true is not called within max_time
        def bump_uptime(name, key)
          @uptime_checks[name].kill if @uptime_checks[name]

          # FIXME TODO thread safety,this could be called from 2 places at the same time
          @uptime_checks[name] = Catcher.thread("uptime check for #{name}") do
            sleep key[:opts][:max_time]
            put(name, false, Time.now)
          end
        end

        # only if key_type is provided, it will create key with given name if it doesn't exist yet
        def get_key(name, key_type=nil)
          name = name.to_s
          return @keys_cache[name] if @keys_cache[name]

          opts = { # defaults
            # don't add points with the same value as previous one if they time diff < N
            same_value_resolution: 600
          }

          type_opts = Hash.new({}) # type defaults TODO move somewhere else
          type_opts[:uptime] = {
            # time without update that is considered as downtime,
            # TODO naming: threshold, freqency, max_gap?
            max_time: 100
          }

          key = @db[:keys].first(name: name)

          if key
            opts.merge! type_opts[ key[:key_type].to_sym ]
            opts.merge! symbolize_keys(JSON.load(key[:key_opts_json])) if key[:key_opts_json] && !key[:key_opts_json].empty?
            @keys_cache[name] = {id: key[:id], type: key[:key_type]}.merge(opts: opts)
          else
            return nil unless key_type
            raise "key creation failed" unless create_key(name, key_type)
            get_key name
          end
        end

        # Called on start to make sure to take care of uptime values that are currently set to true
        def init_uptime_checks
          keys = @db[:keys].where(key_type: 'uptime').each do |k|
            name = k[:name]
            time, value = last(name)
            bump_uptime(name, get_key(name)) if value == true
          end
        end

        # for reasons unknown to me sequel returns string instead of time object for sqlite with our custom select
        def time_wrap(obj)
          obj.kind_of?(String) ? Time.parse(obj) : obj
        end

        # TODO move to Base or storage, definitely not database specific
        def notify_change(key, prev, curr)
          return unless @change_notifications[key]
          prev_time, prev_value = prev
          curr_time, curr_value = curr
          @change_notifications[key].each do |block|
            # TODO rescue exceptions?
            change = {
              key: key, # provide key in case some pattern matching is implmented later e.g. notify on foo__*
              curr: curr_value, # FIXME deprecated, kept only for compatibility
              value: curr_value,
              time: curr_time,
              previous_value: prev_value
            }
            block.call(change)
          end
        end

        def type_table(type_name)
          prefixes = {
            boolean: 'boolean',
            numeric: 'numeric',
            string: 'string',
            uptime: 'boolean'
          }
          pfx = prefixes[type_name.to_sym]
          raise "unknown type" unless pfx
          "#{pfx}_data_points".to_sym
        end

        def prepare_database
          @db.create_table?(:datasets) do
            primary_key :id
            column :name, String
          end

          @db.create_table?(:keys) do
            primary_key :id
            column :dataset_id, :integer, index: true
            column :name, String
            column :key_type, String, index: true
            column :key_opts_json, String, text: true
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
