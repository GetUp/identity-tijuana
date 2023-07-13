require "identity_tijuana/redis_helper"

module IdentityTijuana
  module MutexHelper
    include IdentityTijuana::RedisHelper

    module ClassMethods
      def acquire_mutex_lock(method_name, sync_id)
        mutex_name = "#{SYSTEM_NAME}:mutex:#{method_name}"
        new_mutex_expiry = DateTime.now + MUTEX_EXPIRY_DURATION
        mutex_acquired = set_redis_date(mutex_name, new_mutex_expiry, true)
        unless mutex_acquired
          mutex_expiry = get_redis_date(mutex_name)
          if mutex_expiry.past?
            unless worker_currently_running?(method_name, sync_id)
              delete_redis_date(mutex_name)
              mutex_acquired = set_redis_date(mutex_name, new_mutex_expiry, true)
            end
          end
        end
        mutex_acquired
      end

      def release_mutex_lock(method_name)
        mutex_name = "#{SYSTEM_NAME}:mutex:#{method_name}"
        delete_redis_date(mutex_name)
      end
    end

    extend ClassMethods
    def self.included(other)
      other.extend(ClassMethods)
    end
  end
end