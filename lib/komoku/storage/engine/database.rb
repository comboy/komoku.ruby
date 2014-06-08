require 'sequel'
require 'sqlite3'

module Komoku
  class Storage
    module Engine
      class Database < Base
        def initialize(opts = {})
          # FIXME custom db types
          # FIXME URI from opts
          @db = Sequel.connect "sqlite://tmp/test.db"
          prepare_database
          super
        end

        def put(key, value)
          @db[:numeric_data_points].insert(key_id: key_id(key), value: value, time: Time.now.to_i)
        end

        def last(key)
          ret = @db[:numeric_data_points].where(key_id: key_id(key)).first
          ret && [ret[:time], ret[:value]]
        end

        protected

        def key_id(name)
          key = @db[:keys].first(name: name)
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
