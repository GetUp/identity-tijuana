require 'active_record'
require_relative 'tijuana_test_schema'

module ExternalDatabaseHelpers
  class << self
    def set_external_database_urls(database_url)
      ENV['IDENTITY_DATABASE_URL'] = database_url
      ENV['IDENTITY_READ_ONLY_DATABASE_URL'] = database_url
      ENV['TIJUANA_DATABASE_URL'] = replace_db_name_in_db_url(database_url, 'identity_tijuana_test_client_engine')
      ENV['TIJUANA_READ_ONLY_DATABASE_URL'] = replace_db_name_in_db_url(database_url, 'identity_tijuana_test_client_engine')
    end

    def replace_db_name_in_db_url(database_url, replacement_db_name)
      return database_url.split('/')[0..-2].join('/') + '/' + replacement_db_name
    end

    def setup
      ExternalDatabaseHelpers.create_database
    ensure
      ActiveRecord::Base.establish_connection ENV['IDENTITY_DATABASE_URL']
    end

    def create_database
      puts 'Rebuilding test database for Tijuana...'

      tijuana_db = ENV['TIJUANA_DATABASE_URL'].split('/').last
      ActiveRecord::Base.connection.execute("DROP DATABASE IF EXISTS #{tijuana_db};")
      ActiveRecord::Base.connection.execute("CREATE DATABASE #{tijuana_db};")
      ActiveRecord::Base.establish_connection ENV['TIJUANA_DATABASE_URL']
      CreateTijuanaTestDb.new.up
    end

    def clean
      IdentityTijuana::Unsubscribe.all.destroy_all
      IdentityTijuana::UserActivityEvent.all.destroy_all
      IdentityTijuana::User.all.destroy_all
      IdentityTijuana::Tagging.all.destroy_all
      IdentityTijuana::Tag.all.destroy_all
      IdentityTijuana::Postcode.all.destroy_all
      IdentityTijuana::Campaign.all.destroy_all
    end
  end
end
