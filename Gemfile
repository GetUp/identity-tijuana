source 'https://rubygems.org'

gemspec
gem 'rails'
gem 'pg', '~> 0.18'
gem 'active_model_serializers', '~> 0.10.7'
gem 'httpclient'
gem 'sidekiq', '~> 5.2.9'
gem 'sidekiq-batch'
gem 'sidekiq-limit_fetch'
gem 'sidekiq-unique-jobs'

group :development, :test do
  gem 'phony'
  gem 'faker'
  gem 'dotenv-rails'
  gem 'byebug', platforms: [:mri, :mingw, :x64_mingw]
  gem 'rspec-rails'
  gem 'rspec-mocks'
  gem 'database_cleaner'
  gem 'factory_bot_rails'
  gem 'rubocop', require: false
  gem 'pry'
  gem 'pry-rails'
  gem 'pry-byebug'
  gem 'spring-commands-rspec'
end
