module ExternalSystems::IdentityTijuana
  FactoryBot.define do
    factory :tijuana_campaign, class: Campaign do
      name { Faker::Educator.course_name }
      pillar { Faker::Educator.subject }
    end
  end
end
