module IdentityTijuana
  FactoryBot.define do
    factory :tijuana_user, class: User do
      first_name { Faker::Name.first_name }
      last_name { Faker::Name.last_name }
      email { Faker::Internet.email }

      factory :tijuana_user_with_home_number do
        home_number { "612#{::Kernel.rand(10_000_000..99_999_999)}" }
      end

      factory :tijuana_user_with_mobile_number do
        mobile_number { "614#{::Kernel.rand(10_000_000..99_999_999)}" }
      end

      factory :tijuana_user_with_address do
        street_address { Faker::Address.street_address }
        suburb { Faker::Address.city }
        postcode { IdentityTijuana::Postcode.new(number: Faker::Address.zip_code, state: Faker::Address.state_abbr) }
      end

      factory :tijuana_user_with_the_lot do
        home_number { "612#{::Kernel.rand(10_000_000..99_999_999)}" }
        mobile_number { "614#{::Kernel.rand(10_000_000..99_999_999)}" }
        street_address { Faker::Address.street_address }
        suburb { Faker::Address.city }
        postcode { IdentityTijuana::Postcode.new(number: Faker::Address.zip_code, state: Faker::Address.state_abbr) }
      end

      factory :tijuana_user_with_everything do
        home_number { "612#{::Kernel.rand(10_000_000..99_999_999)}" }
        mobile_number { "614#{::Kernel.rand(10_000_000..99_999_999)}" }
        street_address { Faker::Address.street_address }
        suburb { Faker::Address.city }
        postcode { IdentityTijuana::Postcode.new(number: Faker::Address.zip_code, state: Faker::Address.state_abbr) }
        country_iso { Faker::Address.country_code }
        encrypted_password { Faker::Internet.password }
        password_salt { Faker::Crypto.md5 }
        reset_password_token { Faker::Crypto.md5 }
        reset_password_sent_at { 20.days.ago }
        remember_created_at { 2.hours.ago }
        current_sign_in_at { 1.hours.ago }
        last_sign_in_at { 10.days.ago }
        last_sign_in_ip { Faker::Internet.ip_v4_address }
        random { rand(0.0..0.001) }
        notes { Faker::Lorem.paragraph }
        quick_donate_trigger_id { Faker::Alphanumeric.alphanumeric(number: 12) }
        facebook_id { Faker::Alphanumeric.alphanumeric(number: 12) }
        otp_secret_key { Faker::Alphanumeric.alphanumeric(number: 32) }
        tracking_token { Faker::Alphanumeric.alphanumeric(number: 8) }
      end
    end
  end
end
