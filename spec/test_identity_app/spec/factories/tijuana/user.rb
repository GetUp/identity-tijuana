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
    end
  end
end
