module IdentityTijuana
  FactoryBot.define do
    factory :call_outcome, class: CallOutcome do
      disposition { "No Answer" }
      campaign_type { "admin_outbound" }
      campaign_code { "admin" }
      campaign_name { "Donations Admin" }
    end
  end
end
