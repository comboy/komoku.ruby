module Komoku
  module Helpers
    def symbolize_keys(hash)
      hash.inject({}){|result, (key, value)|
        new_key = key.kind_of?(String) ? key.to_sym : key
        new_value = value.kind_of?(Hash) ? symoblize_keys(value) : value
        result[new_key] = new_value
        result
      }
    end
  end
end
