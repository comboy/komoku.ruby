require 'sequel'
require 'sqlite3'
require 'logger'

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

        def fetch(key, opts = {})
          scope = @db[:numeric_data_points].where(key_id: key_id(key))
          scope = scope.where('time > :since', since: opts[:since]) if opts[:since]
          # TODO use date_trunc for pg or do some reasonable indexes
          scope = scope.select_group(Sequel.lit "strftime('%s',time)/60").select_append { avg(value_avg).as(value_avg) } if opts[:resolution]
          rows = scope.limit(100) # TODO limit option
          rows = scope.all
          rows.map {|r| [r[:time], r[:value_avg]]}
        end

        def put(key, value, time)
          # read previous values if we need them for notification
          last_time, last_value = last(key) if @change_notifications[key]

          # FIXME TODO steps definitions
          default_step = 5 # seconds

          @db[:numeric_data_points].insert(key_id: key_id(key), value_avg: value, time: time, value_count: 1, value_max: value, value_min: value) #TODO fill in other fields

          # notify about the change
          notify_change key, last_value, value if @change_notifications[key] && ( last_time.nil? || (time > last_time) && (last_value != value) )
        end

        def last(key)
          # OPTIMIZE caching
          ret = @db[:numeric_data_points].where(key_id: key_id(key)).order(Sequel.desc(:id)).first
          ret && [ret[:time], ret[:value_avg]]
        end

        # Return list of all stored keys
        def keys
          # TODO keys are strings, type is symbol, inconsistent
          Hash[* @db[:keys].map{|k| [k[:name], {type: k[:key_type]}]}.flatten]
        end

        def stats
          {
            data_points_count: @db[:numeric_data_points].count
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

        protected

        def key_id(name)
          key = @db[:keys].first(name: name.to_s)
          if key
            key[:id]
          else
            # We need to create a new key, insert returns the id
            @db[:keys].insert(name: name, key_type: 'numeric')
          end
        end

        def notify_change(key, last_value, value)
          return unless @change_notifications[key]
          @change_notifications[key].each do |block|
            # we provide key as one of the args in case some pattern matching is implmented later e.g. notify on foo__*
            # TODO rescue exceptions?
            block.call(key, last_value, value)
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
            column :key_id, :integer
            column :time, :timestamp, index: true
            column :value_avg, :double
            column :value_count, :integer
            column :value_max, :double
            column :value_min, :double
            column :value_step, :integer
          end

        end
      end
    end
  end
end
