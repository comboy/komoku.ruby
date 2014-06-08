module Komoku
  class Storage

    class Dataset

      def initialize(engine, name)
        @engine = engine
        @name = name
      end

      def put(key, value)
        @engine.put key,value
        # TODO cache
      end

      def get(key)
        # TODO cache
        @engine.get key
      end

    end

  end
end
