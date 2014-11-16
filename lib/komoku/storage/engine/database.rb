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
          scope = scope.select_group(Sequel.lit "strftime('%s',time)/60").select_append { avg(value).as(value) } if opts[:resolution]
          rows = scope.all
          rows.map {|r| [r[:time], r[:value]]}
        end

        def put(key, value, time)
          # read previous values if we need them for notification
          last_time, last_value = last(key) if @change_notifications[key]

          @db[:numeric_data_points].insert(key_id: key_id(key), value: value, time: time)

          # notify about the change
          notify_change key, last_value, value if @change_notifications[key] && ( last_time.nil? || (time > last_time) && (last_value != value) )
        end

        def last(key)
          # OPTIMIZE caching
          ret = @db[:numeric_data_points].where(key_id: key_id(key)).order(Sequel.desc(:id)).first
          ret && [ret[:time], ret[:value]]
        end

        def keys
          @db[:keys].map{|k| k[:name]}
        end

        def stats
          {
            data_points_count: @db[:numeric_data_points].count
          }
        end

        def on_change(key, &block)
          @change_notifications[key] ||= []
          @change_notifications[key] << block
        end

        protected

        def key_id(name)
          key = @db[:keys].first(name: name.to_s)
          if key
            key[:id]
          else
            # We need to create a new key, insert returns the id
            @db[:keys].insert(name: name)
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
            column :dataset_id, :integer
            column :name, :string
            column :key_type, :string
          end

          @db.create_table?(:numeric_data_points) do
            primary_key :id
            column :key_id, :integer
            column :value, :float
            column :time, :timestamp
          end

          # TODO FIXME indexes are quite important indeed
        end
      end
    end
  end
end
