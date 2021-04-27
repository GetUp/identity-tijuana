module ExternalSystems::IdentityTijuana
  FactoryBot.define do
    factory :tijuana_activity, class: UserActivityEvent do
      activity { Faker::Verb.base }
    end
  end
end
