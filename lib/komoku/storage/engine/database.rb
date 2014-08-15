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
          @db[:numeric_data_points].insert(key_id: key_id(key), value: value, time: time)
        end

        def last(key)
          ret = @db[:numeric_data_points].where(key_id: key_id(key)).first
          ret && [ret[:time], ret[:value]]
        end

        def keys
          @db[:keys].map{|k| k[:name]}
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
            column :key_id, :integer
            column :value, 'NUMERIC(10)'
            column :time, :timestamp
          end
        end
      end
    end
  end
end
