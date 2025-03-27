# This patch allows accessing the settings hash with dot notation
class Hash
  def method_missing(method, *opts)
    m = method.to_s
    return self[m] if key?(m)
    super
  end
end

class Settings
  def self.tijuana
    return {
      "database_url" => ENV['TIJUANA_DATABASE_URL'],
      "read_only_database_url" => ENV['TIJUANA_DATABASE_URL'],
      "api" => {
        "url" => ENV['TIJUANA_API_URL'],
        "secret" => ENV['TIJUANA_API_SECRET']
      },
      "push_batch_amount" => nil,
      "pull_batch_amount" => nil,
    }
  end

  def self.app
    return {
      "inbound_url" => "http://localhost/inbound_url",
    }
  end

  def self.databases
    return {
      "extensions_schemas" => {
        "core" => 'public',
        "mailer" => 'public'
      },
      "zip_schema" => false,
      "zip_primary_key" => false
    }
  end

  def self.ghoster
    return {
      "email_domain" => "example.com"
    }
  end

  def self.redis_url
    return ENV['REDIS_URL']
  end

  def self.redis
    return {
      "pool_size" => 5,
    }
  end

  def self.sidekiq_redis_url
    return ENV['REDIS_URL']
  end

  def self.sidekiq_redis_pool_size
    return 5
  end

  def self.sidekiq
    return {
      "log_level" => "WARN",
      "unique_jobs_debug" => false,
      "unique_jobs_reaper_type" => 'none',
      "unique_jobs_reaper_count" => 100,
      "unique_jobs_reaper_interval" => 30,
      "unique_jobs_reaper_timeout" => 2,
      "unique_jobs_reaper_resurrector_interval" => 1800
    }
  end

  def self.deduper
    return {
      "enabled" => false
    }
  end

  def self.email
    return {
      "unsubscribe_url" => "http://localhost/unsubscribe",
    }
  end

  def self.geography
    return {}
  end

  def self.options
    return {
      "use_redshift" => true,
      "default_phone_country_code" => '61',
      "ignore_name_change_for_donation" => true
    }
  end
end
