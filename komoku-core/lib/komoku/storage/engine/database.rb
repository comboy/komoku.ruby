require 'sequel'
require 'sqlite3'
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
          super
        end

        def fetch(name, opts = {})
          return [] unless key = get_key(name)
          scope = @db[:numeric_data_points].where(key_id: key[:id])
          scope = scope.where('time > :since', since: opts[:since]) if opts[:since]
          # TODO use date_trunc for pg (main use case)
          if opts[:step]
            s = step opts[:step] # see Engine::Base#step
            f_time = "(strftime('%s',time)/#{s[:span]})*#{s[:span]}"
            scope = scope.select(Sequel.lit "datetime(#{f_time}, 'unixepoch') AS time").group(Sequel.lit f_time).select_append { avg(value_avg).as(value_avg) }
          end
          scope = scope.order(Sequel.desc(:time)).limit(100) # TODO limit option and order, these are defaults for testing
          #puts "SQL: #{scope.sql}"
          rows = scope.all
          rows.reverse.map do |r|
            # for reasons unknown to me sequel returns string instead of time object for sqlite with our custom  select
            time = r[:time].kind_of?(String) ? Time.parse(r[:time]) : r[:time]
            value = r[:value_avg]
            [time, value]
          end
        end

        def put(name, value, time)
          # read previous values if we need them for notification
          last_time, last_value = last(name) if @change_notifications[name]

          # FIXME TODO steps definitions
          default_step = 5 # seconds
          key_type = guess_key_type(value)
          key = get_key(name, key_type)

          case key_type
          when 'boolean'
            @db[:boolean_data_points].insert(key_id: key[:id], value: value, time: time)
          else
            @db[:numeric_data_points].insert(key_id: key[:id], value_avg: value, time: time, value_count: 1, value_max: value, value_min: value)
          end

          # notify about the change
          notify_change name, last_value, value if @change_notifications[name] && ( last_time.nil? || (time > last_time) && (last_value != value) )
        end

        def last(name)
          # OPTIMIZE caching
          return nil unless key = get_key(name)
          if key[:type] == 'boolean'
            ret = @db[:boolean_data_points].where(key_id: key[:id]).order(Sequel.desc(:time)).first
            ret && [ret[:time], ret[:value]]
          else
            ret = @db[:numeric_data_points].where(key_id: key[:id]).order(Sequel.desc(:time)).first
            ret && [ret[:time], ret[:value_avg]]
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

        protected

        # if key_type is provided, it will create key with given name if it doesn't exist yet
        def get_key(name, key_type=nil)
          # OPTIMIZE caching, key type and id won't ever change
          key = @db[:keys].first(name: name.to_s)
          if key
            {id: key[:id], type: key[:key_type]}
          else
            return nil unless key_type
            # We need to create a new key, insert returns the id
            id = @db[:keys].insert(name: name, key_type: key_type)
            {id: id, type: key_type}
          end
        end

        def notify_change(key, last_value, value)
          return unless @change_notifications[key]
          @change_notifications[key].each do |block|
            # we provide key as one of the args in case some pattern matching is implmented later e.g. notify on foo__*
            # TODO rescue exceptions?
            block.call(key, value, last_value)
          end
        end

        def prepare_database
          @db.create_table?(:datasets) do
            primary_key :id
            column :id, :primary_key
            column :name, :string
          end

          @db.create_table?(:keys) do
            #column :id, :primary_key
            primary_key :id
            column :dataset_id, :integer, index: true
            column :name, :string
            column :key_type, :string, index: true
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
            # TODO aggregation possible within the same table?
          end

        end
      end
    end
  end
end
