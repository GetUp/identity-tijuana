source 'https://rubygems.org'

gemspec
gem 'rails', '~> 7.0.0'
gem 'pg'
gem 'active_model_serializers'
gem 'httpclient'
gem 'sidekiq'

group :development, :test do
  gem 'faker'
  gem 'dotenv-rails'
  gem 'byebug', platforms: [:mri, :mingw, :x64_mingw]
  gem 'rspec-rails'
  gem 'rspec-mocks'
  gem 'database_cleaner-active_record'
  gem 'database_cleaner-redis'
  gem 'factory_bot_rails'
  gem 'rubocop'
  gem 'pry'
  gem 'pry-rails'
  gem 'pry-byebug'
  gem 'spring-commands-rspec'
  gem 'webmock'

  # Id-specific deps for testing
  gem 'audited'
  gem 'phony'
  gem 'sidekiq-batch'
  gem 'sidekiq-limit_fetch'
  gem 'sidekiq-unique-jobs'
  gem 'sprockets-rails'
end
