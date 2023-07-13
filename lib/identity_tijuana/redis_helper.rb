module IdentityTijuana
  module RedisHelper
    module ClassMethods
      private

      def get_redis_date(redis_identifier, default_value=Time.at(0))
        date_str = Sidekiq.redis { |r| r.get redis_identifier }
        date_str ? Time.parse(date_str) : default_value
      end

      def set_redis_date(redis_identifier, date_time_value, as_mutex=false)
        date_str = date_time_value.utc.strftime("%Y-%m-%d %H:%M:%S.%9N %z") # Ensures fractional seconds are retained
        if as_mutex
          Sidekiq.redis { |r| r.setnx redis_identifier, date_str }
        else
          Sidekiq.redis { |r| r.set redis_identifier, date_str }
        end
      end

      def delete_redis_date(redis_identifier)
        Sidekiq.redis { |r| r.del redis_identifier }
      end
    end

    extend ClassMethods
    def self.included(other)
      other.extend(ClassMethods)
    end
  end
end
