require 'rails_helper'
require 'identity_tijuana'

User = ExternalSystems::IdentityTijuana::User
Push = ExternalSystems::IdentityTijuana::Push

RSpec.configure do |config|
  config.before(:all) do
    FactoryBot.definition_file_paths << File.expand_path('../../factories', __FILE__)
    FactoryBot.reload
  end
end

RSpec.describe ExternalSystems::IdentityTijuana do
  before(:each) do
    DatabaseCleaner[:active_record].clean_with(:truncation, :except => %w[permissions subscriptions])
    DatabaseCleaner[:active_record, db: ExternalSystems::IdentityTijuana::Push].strategy = :truncation
    DatabaseCleaner[:active_record, db: ExternalSystems::IdentityTijuana::Push].start
    DatabaseCleaner[:active_record].clean
  end

  context '#push_updated_members' do
    before do
      allow(Settings).to receive_message_chain("options.default_phone_country_code") { '61' }
      allow(Settings).to receive_message_chain("options.allow_subscribe_via_upsert_member") { true }
      allow(Settings).to receive_message_chain("options.allow_upsert_create_subscriptions") { true }
      allow(Settings).to receive_message_chain("options.default_member_opt_in_subscriptions") { true }
      allow(Settings).to receive_message_chain("options.default_mobile_phone_national_destination_code") { 4 }
      allow(Settings).to receive_message_chain("tijuana.pull_batch_amount") { nil }
      allow(Settings).to receive_message_chain("tijuana.push_batch_amount") { nil }
    end

    it 'adds users' do
      member = FactoryBot.create(:member)

      ExternalSystems::IdentityTijuana.push_updated_members() {}

      new_user = User.find_by(email: member.email)
      expect(new_user).to have_attributes(first_name: member.first_name)
      expect(new_user).to have_attributes(last_name: member.last_name)
      expect(User.count).to eq(1)
    end

    it 'upserts users based on email' do
      member = FactoryBot.create(:member)
      user_with_email = FactoryBot.create(:tijuana_user)
      user_with_email.update_attributes(email: member.email)
      expect(User.count).to eq(1)
      expect(User.first).not_to have_attributes(first_name: member.first_name)

      ExternalSystems::IdentityTijuana.push_updated_members() {}

      new_user = User.find_by(email: member.email)
      expect(new_user).to have_attributes(first_name: member.first_name)
      expect(new_user).to have_attributes(last_name: member.last_name)
      expect(User.count).to eq(1)
    end

    it 'subscribes users to email, calling and sms' do
      member = FactoryBot.create(:member)
      member.subscribe_calling()
      member.subscribe_text_blasts()
      user_with_email_and_calling = FactoryBot.create(:tijuana_user, is_member: true, do_not_call: false, do_not_sms: false)
      user_with_email_and_calling.update_attributes(email: member.email)

      expect(member.is_subscribed_to?(Subscription::EMAIL_SUBSCRIPTION.id)).to eq(true)
      expect(member.is_subscribed_to?(Subscription::CALLING_SUBSCRIPTION.id)).to eq(true)
      expect(member.is_subscribed_to?(Subscription::SMS_SUBSCRIPTION.id)).to eq(true)

      ExternalSystems::IdentityTijuana.push_updated_members() {}

      user_with_email_and_calling.reload
      expect(user_with_email_and_calling.is_member).to eq(true)
      expect(user_with_email_and_calling.do_not_call).to eq(false)
      expect(user_with_email_and_calling.do_not_sms).to eq(false)
    end

    it 'unsubscribes users' do
      unsubscribed_member = FactoryBot.create(:member_unsubscribed)
      user_with_email_and_calling = FactoryBot.create(:tijuana_user, is_member: true, do_not_call: false, do_not_sms: false)
      user_with_email_and_calling.update_attributes(email: unsubscribed_member.email)

      expect(unsubscribed_member.is_subscribed_to?(Subscription::EMAIL_SUBSCRIPTION.id)).to eq(false)
      expect(unsubscribed_member.is_subscribed_to?(Subscription::CALLING_SUBSCRIPTION.id)).to eq(false)
      expect(unsubscribed_member.is_subscribed_to?(Subscription::SMS_SUBSCRIPTION.id)).to eq(false)

      ExternalSystems::IdentityTijuana.push_updated_members() {}

      user_with_email_and_calling.reload
      expect(user_with_email_and_calling.is_member).to eq(false)
      expect(user_with_email_and_calling.do_not_call).to eq(true)
      expect(user_with_email_and_calling.do_not_sms).to eq(true)
    end

    it 'does not update users based on phone' do
      user = FactoryBot.create(:tijuana_user, mobile_number: '0427700300')
      member = FactoryBot.create(:member)
      member.update_phone_number('61427700300')

      ExternalSystems::IdentityTijuana.push_updated_members() {}

      user_with_phone = User.find_by_mobile_number('0427700300')
      expect(user_with_phone).to have_attributes(first_name: user.first_name)
      expect(user_with_phone).to have_attributes(last_name: user.last_name)
      expect(User.count).to eq(2)
    end

    it 'correctly adds phone numbers' do
      member = FactoryBot.create(:member, name: 'Phone McPhone', email: 'phone@example.com')
      member.update_phone_number('61427700300', 'mobile')
      member.update_phone_number('61281882888', 'landline')

      expect(member.phone_numbers.mobile.first&.phone).to eq('61427700300')
      expect(member.phone_numbers.landline.first&.phone).to eq('61281882888')

      ExternalSystems::IdentityTijuana.push_updated_members() {}

      expect(User.count).to eq(1)
      expect(User.first.home_number).to eq('61281882888')
      expect(User.first.mobile_number).to eq('61427700300')
    end

    it 'correctly adds addresses' do
      member = FactoryBot.create(:member, name: 'Address McAdd', email: 'address@example.com')
      member.update_address(line1: '18 Mitchell Street', town: 'Bondi', postcode: 2026, state: 'NSW', country: 'Australia')

      ExternalSystems::IdentityTijuana.push_updated_members() {}

      expect(User.count).to eq(1)
      expect(User.first).to have_attributes(first_name: 'Address', last_name: 'McAdd', email: 'address@example.com')
      expect(User.first).to have_attributes(street_address: '18 Mitchell Street', suburb: 'Bondi')
      expect(User.first.postcode).to have_attributes(number: '2026', state: 'NSW')
    end
  end

  context '#push_mailings' do
    it 'pushes a single mailing' do
      list = FactoryBot.create(:list, member_count: 10)
      mailing = Mailer::Mailing.create!(list_id: list.id, from_name: 'test')

      ExternalSystems::IdentityTijuana.push_mailings() {}

      puts Push.all.map(&:id)
      puts Mailer::Mailing.all.map(&:id)

      expect(Push.count).to eq(1)
    end
  end
end
