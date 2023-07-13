FactoryBot.define do
  factory :subscription do
    factory :calling_subscription do
      id { Subscription::CALLING_SUBSCRIPTION }
      name { 'Calling' }
      slug { 'default:calling' }
      initialize_with {
        Subscription.find_or_create_by!(
          id: id,
          name: name,
          slug: slug
        )
      }
    end
    factory :email_subscription do
      id { Subscription::EMAIL_SUBSCRIPTION }
      name { 'Email' }
      slug { 'default:email' }
      initialize_with {
        Subscription.find_or_create_by!(
          id: id,
          name: name,
          slug: slug
        )
      }
    end
    factory :sms_subscription do
      id { Subscription::SMS_SUBSCRIPTION }
      name { 'SMS' }
      slug { 'default:sms' }
      initialize_with {
        Subscription.find_or_create_by!(
          id: id,
          name: name,
          slug: slug
        )
      }
    end
  end
end
