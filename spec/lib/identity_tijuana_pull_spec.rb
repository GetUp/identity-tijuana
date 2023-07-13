require 'rails_helper'

describe IdentityTijuana do

  before(:all) do
    @sync_id = 1
    Sidekiq::Testing.inline!
  end

  def phone_numbers_are_equivalent(phone1, phone2)
    # Compare only the last 8 digits to sidestep issues with formatting of the prefix.
    ph1 = phone1 ? phone1[-8..-1] || phone1 : nil
    ph2 = phone2 ? phone2[-8..-1] || phone2 : nil
    ph1 == ph2
  end

  context '#pull' do
    before(:each) do
      @external_system_params = JSON.generate({'pull_job' => 'fetch_user_updates'})
    end

    context 'with valid parameters' do
      it 'should call the corresponding method'  do
        expect(IdentityTijuana).to receive(:fetch_user_updates).exactly(1).times.with(1)
        IdentityTijuana.pull(@sync_id, @external_system_params)
      end
    end
  end

  context '#fetch_campaign_updates' do
    context 'TJ campaign/ID issue handling' do
      before do
        @tj_campaign_1 = IdentityTijuana::Campaign.create(name: 'Campaign 1')
        @tj_campaign_2 = IdentityTijuana::Campaign.create(name: 'Campaign 2')
      end

      it 'creates TJ campaigns as issues in Identity' do
        IdentityTijuana.fetch_campaign_updates(@sync_id) {}
        expect(Issue.count).to eq(2)
      end

      it 'updates changed TJ campaigns in Identity' do
        IdentityTijuana.fetch_campaign_updates(@sync_id) {}
        expect(Issue.find_by(external_id: @tj_campaign_1.id, external_source: 'tijuana').name).to eq('Campaign 1')
        @tj_campaign_1.name = 'Campaign 1 changed'
        @tj_campaign_1.save!
        IdentityTijuana.fetch_campaign_updates(@sync_id) {}
        expect(Issue.find_by(external_id: @tj_campaign_1.id, external_source: 'tijuana').name).to eq('Campaign 1 changed')
      end

      it 'doesnt create deleted TJ campaigns as issues in Identity' do
        @tj_campaign_2.deleted_at = DateTime.now.utc
        @tj_campaign_2.save!
        IdentityTijuana.fetch_campaign_updates(@sync_id) {}
        expect(Issue.count).to eq(1)
      end

      it 'removes deleted TJ campaigns from Identity' do
        IdentityTijuana.fetch_campaign_updates(@sync_id) {}
        expect(Issue.count).to eq(2)
        @tj_campaign_2.deleted_at = DateTime.now.utc
        @tj_campaign_2.save!
        IdentityTijuana.fetch_campaign_updates(@sync_id) {}
        expect(Issue.count).to eq(1)
      end
    end
  end

  context '#fetch_user_updates' do
    before(:each) do
      @email_sub = FactoryBot.create(:email_subscription)
      @calling_sub = FactoryBot.create(:calling_subscription)
      @sms_sub = FactoryBot.create(:sms_subscription)
      allow(Settings).to receive_message_chain("options.use_redshift") { false }
      allow(Settings).to receive_message_chain("options.allow_subscribe_via_upsert_member") { true }
      allow(Settings).to receive_message_chain("options.default_member_opt_in_subscriptions") { true }
      allow(Settings).to receive_message_chain("options.default_phone_country_code") { '61' }
      allow(Settings).to receive_message_chain("options.default_mobile_phone_national_destination_code") { '4' }
      allow(Settings).to receive_message_chain("tijuana.email_subscription_id") { @email_sub.id }
      allow(Settings).to receive_message_chain("tijuana.calling_subscription_id") { @calling_sub.id }
      allow(Settings).to receive_message_chain("tijuana.sms_subscription_id") { @sms_sub.id }
      allow(Settings).to receive_message_chain("tijuana.pull_batch_amount") { nil }
      allow(Settings).to receive_message_chain("tijuana.push_batch_amount") { nil }
    end

    context 'when creating' do
      it 'creates new members in Identity' do
        u = FactoryBot.create(:tijuana_user_with_the_lot)
        IdentityTijuana.fetch_user_updates(@sync_id) {}
        m = Member.find_by(email: u.email)
        expect(m).to have_attributes(first_name: u.first_name, last_name: u.last_name)
        expect(phone_numbers_are_equivalent(m.phone_numbers.mobile.first&.phone, u.mobile_number)).to eq(true)
        expect(phone_numbers_are_equivalent(m.phone_numbers.landline.first&.phone, u.home_number)).to eq(true)
        expect(m.address).to have_attributes(line1: u.street_address, town: u.suburb,
                                             state: u.postcode.state, postcode: u.postcode.number)
      end
      it 'creates new users in Tijuana' do
        m = FactoryBot.create(:member_with_the_lot)
        IdentityTijuana::Postcode.create(number: m.address.postcode, state: m.address.state)
        IdentityTijuana.fetch_user_updates(@sync_id) {}
        u = User.find_by(email: m.email)
        expect(u).to have_attributes(first_name: m.first_name, last_name: m.last_name)
        expect(u).to have_attributes(street_address: m.address.line1, suburb: m.address.town)
        expect(u.postcode.number).to eq(m.address.postcode)
        expect(u.postcode.state).to eq(m.address.state)
      end
    end

    context 'when merging' do
      context 'names' do
        it 'merges a missing name to Identity' do
          u = FactoryBot.create(:tijuana_user)
          m = FactoryBot.create(:member, email: u.email, first_name: nil, middle_names: nil, last_name: nil)
          first_name = u.first_name
          last_name = u.last_name
          IdentityTijuana.fetch_user_updates(@sync_id) {}
          u.reload
          m.reload
          expect(u).to have_attributes(first_name: first_name, last_name: last_name)
          expect(m).to have_attributes(first_name: first_name, last_name: last_name)
        end
        it 'merges a missing name to Tijuana' do
          m = FactoryBot.create(:member)
          u = FactoryBot.create(:tijuana_user, email: m.email, first_name: nil, last_name: nil)
          first_name = m.first_name
          last_name = m.last_name
          IdentityTijuana.fetch_user_updates(@sync_id) {}
          u.reload
          m.reload
          expect(u).to have_attributes(first_name: first_name, last_name: last_name)
          expect(m).to have_attributes(first_name: first_name, last_name: last_name)
        end
        it 'merges a more complete name to Identity' do
          u = FactoryBot.create(:tijuana_user)
          m = FactoryBot.create(:member, email: u.email, first_name: u.first_name, middle_names: nil, last_name: nil)
          first_name = u.first_name
          last_name = u.last_name
          IdentityTijuana.fetch_user_updates(@sync_id) {}
          u.reload
          m.reload
          expect(u).to have_attributes(first_name: first_name, last_name: last_name)
          expect(m).to have_attributes(first_name: first_name, last_name: last_name)
        end
        it 'merges a more complete name to Tijuana' do
          m = FactoryBot.create(:member)
          u = FactoryBot.create(:tijuana_user, email: m.email, first_name: m.first_name, last_name: nil)
          first_name = m.first_name
          last_name = m.last_name
          IdentityTijuana.fetch_user_updates(@sync_id) {}
          u.reload
          m.reload
          expect(u).to have_attributes(first_name: first_name, last_name: last_name)
          expect(m).to have_attributes(first_name: first_name, last_name: last_name)
        end
        it 'merges a conflicting name to Identity if the most recent change was in Tijuana' do
          m = FactoryBot.create(:member)
          u = FactoryBot.create(:tijuana_user, email: m.email)
          first_name = u.first_name
          last_name = u.last_name
          IdentityTijuana.fetch_user_updates(@sync_id) {}
          u.reload
          m.reload
          expect(u).to have_attributes(first_name: first_name, last_name: last_name)
          expect(m).to have_attributes(first_name: first_name, last_name: last_name)
        end
        it 'merges a conflicting name to Tijuana if the most recent change was in Identity' do
          u = FactoryBot.create(:tijuana_user)
          m = FactoryBot.create(:member, email: u.email)
          first_name = m.first_name
          last_name = m.last_name
          IdentityTijuana.fetch_user_updates(@sync_id) {}
          u.reload
          m.reload
          expect(u).to have_attributes(first_name: first_name, last_name: last_name)
          expect(m).to have_attributes(first_name: first_name, last_name: last_name)
        end
      end
      context 'mobile numbers' do
        it 'merges a missing mobile number to Identity' do
          u = FactoryBot.create(:tijuana_user_with_mobile_number)
          m = FactoryBot.create(:member, email: u.email)
          mobile_number = u.mobile_number
          IdentityTijuana.fetch_user_updates(@sync_id) {}
          u.reload
          m.reload
          expect(u).to have_attributes(mobile_number: mobile_number)
          expect(phone_numbers_are_equivalent(mobile_number, m.phone_numbers.mobile.first&.phone)).to eq(true)
        end
        it 'merges a missing mobile number to Tijuana' do
          m = FactoryBot.create(:member_with_mobile)
          u = FactoryBot.create(:tijuana_user, email: m.email)
          mobile_number = m.phone_numbers.mobile.first&.phone
          IdentityTijuana.fetch_user_updates(@sync_id) {}
          u.reload
          m.reload
          expect(phone_numbers_are_equivalent(mobile_number, u.mobile_number)).to eq(true)
          expect(m.phone_numbers.mobile.first&.phone).to eq(mobile_number)
        end
        it 'merges a conflicting mobile number to Identity if the most recent change was in Tijuana' do
          m = FactoryBot.create(:member_with_mobile)
          u = FactoryBot.create(:tijuana_user_with_mobile_number, email: m.email)
          mobile_number = u.mobile_number
          IdentityTijuana.fetch_user_updates(@sync_id) {}
          u.reload
          m.reload
          expect(u).to have_attributes(mobile_number: mobile_number)
          expect(phone_numbers_are_equivalent(mobile_number, m.phone_numbers.mobile.first&.phone)).to eq(true)
        end
        it 'merges a conflicting mobile number to Tijuana if the most recent change was in Identity' do
          u = FactoryBot.create(:tijuana_user_with_mobile_number)
          m = FactoryBot.create(:member_with_mobile, email: u.email)
          mobile_number = m.phone_numbers.mobile.first&.phone
          IdentityTijuana.fetch_user_updates(@sync_id) {}
          u.reload
          m.reload
          expect(m.phone_numbers.mobile.first&.phone).to eq(mobile_number)
          expect(u).to have_attributes(mobile_number: mobile_number)
        end
      end
      context 'landline numbers' do
        it 'merges a missing landline number to Identity' do
          u = FactoryBot.create(:tijuana_user_with_home_number)
          m = FactoryBot.create(:member, email: u.email)
          landline_number = u.home_number
          IdentityTijuana.fetch_user_updates(@sync_id) {}
          u.reload
          m.reload
          expect(u).to have_attributes(home_number: landline_number)
          expect(phone_numbers_are_equivalent(landline_number, m.phone_numbers.landline.first&.phone)).to eq(true)
        end
        it 'merges a missing landline number to Tijuana' do
          m = FactoryBot.create(:member_with_landline)
          u = FactoryBot.create(:tijuana_user, email: m.email)
          landline_number = m.phone_numbers.landline.first&.phone
          IdentityTijuana.fetch_user_updates(@sync_id) {}
          u.reload
          m.reload
          expect(phone_numbers_are_equivalent(landline_number, u.home_number)).to eq(true)
          expect(m.phone_numbers.landline.first&.phone).to eq(landline_number)
        end
        it 'merges a conflicting landline number to Identity if the most recent change was in Tijuana' do
          m = FactoryBot.create(:member_with_landline)
          u = FactoryBot.create(:tijuana_user_with_home_number, email: m.email)
          landline_number = u.home_number
          IdentityTijuana.fetch_user_updates(@sync_id) {}
          u.reload
          m.reload
          expect(u).to have_attributes(home_number: landline_number)
          expect(phone_numbers_are_equivalent(landline_number, m.phone_numbers.landline.first&.phone)).to eq(true)
        end
        it 'merges a conflicting landline number to Tijuana if the most recent change was in Identity' do
          u = FactoryBot.create(:tijuana_user_with_home_number)
          m = FactoryBot.create(:member_with_landline, email: u.email)
          landline_number = m.phone_numbers.landline.first&.phone
          IdentityTijuana.fetch_user_updates(@sync_id) {}
          u.reload
          m.reload
          expect(m.phone_numbers.landline.first&.phone).to eq(landline_number)
          expect(u).to have_attributes(home_number: landline_number)
        end
      end
      context 'addresses' do
        it 'merges a missing address to Identity' do
          u = FactoryBot.create(:tijuana_user_with_address)
          m = FactoryBot.create(:member, email: u.email)
          street_address = u.street_address
          suburb = u.suburb
          state = u.postcode.state
          postcode = u.postcode.number
          IdentityTijuana.fetch_user_updates(@sync_id) {}
          u.reload
          m.reload
          expect(u).to have_attributes(street_address: street_address, suburb: suburb)
          expect(u.postcode&.number).to eq(postcode)
          expect(u.postcode&.state).to eq(state)
          expect(m.address).to have_attributes(line1: street_address, town: suburb, state: state, postcode: postcode)
        end
        it 'merges a missing address to Tijuana' do
          m = FactoryBot.create(:member_with_address)
          u = FactoryBot.create(:tijuana_user, email: m.email)
          street_address = m.address.line1
          suburb = m.address.town
          state = m.address.state
          postcode = m.address.postcode
          IdentityTijuana::Postcode.create(number: postcode, state: state)
          IdentityTijuana.fetch_user_updates(@sync_id) {}
          u.reload
          m.reload
          expect(u).to have_attributes(street_address: street_address, suburb: suburb)
          expect(u.postcode&.number).to eq(postcode)
          expect(u.postcode&.state).to eq(state)
          expect(m.address).to have_attributes(line1: street_address, town: suburb, state: state, postcode: postcode)
        end
        it 'merges a more complete address to Identity' do
          u = FactoryBot.create(:tijuana_user_with_address)
          m = FactoryBot.create(:member, email: u.email)
          street_address = u.street_address
          suburb = u.suburb
          state = u.postcode.state
          postcode = u.postcode.number
          FactoryBot.create(:address, member: m, line1: nil, town: nil, state: nil, postcode: postcode)
          IdentityTijuana.fetch_user_updates(@sync_id) {}
          u.reload
          m.reload
          expect(u).to have_attributes(street_address: street_address, suburb: suburb)
          expect(u.postcode&.number).to eq(postcode)
          expect(u.postcode&.state).to eq(state)
          expect(m.address).to have_attributes(line1: street_address, town: suburb, state: state, postcode: postcode)
        end
        it 'merges a more complete address to Tijuana' do
          m = FactoryBot.create(:member_with_address)
          u = FactoryBot.create(:tijuana_user, email: m.email)
          street_address = m.address.line1
          suburb = m.address.town
          state = m.address.state
          postcode = m.address.postcode
          p = IdentityTijuana::Postcode.create(number: postcode, state: state)
          u.postcode = p
          IdentityTijuana.fetch_user_updates(@sync_id) {}
          u.reload
          m.reload
          expect(u).to have_attributes(street_address: street_address, suburb: suburb)
          expect(u.postcode&.number).to eq(postcode)
          expect(u.postcode&.state).to eq(state)
          expect(m.address).to have_attributes(line1: street_address, town: suburb, state: state, postcode: postcode)
        end
        it 'merges a conflicting address to Identity if the most recent change was in Tijuana' do
          m = FactoryBot.create(:member_with_address)
          u = FactoryBot.create(:tijuana_user_with_address, email: m.email)
          street_address = u.street_address
          suburb = u.suburb
          state = u.postcode.state
          postcode = u.postcode.number
          IdentityTijuana.fetch_user_updates(@sync_id) {}
          u.reload
          m.reload
          expect(u).to have_attributes(street_address: street_address, suburb: suburb)
          expect(u.postcode&.number).to eq(postcode)
          expect(u.postcode&.state).to eq(state)
          expect(m.address).to have_attributes(line1: street_address, town: suburb, state: state, postcode: postcode)
        end
        it 'merges a conflicting address to Tijuana if the most recent change was in Identity' do
          u = FactoryBot.create(:tijuana_user_with_address)
          m = FactoryBot.create(:member_with_address, email: u.email)
          street_address = m.address.line1
          suburb = m.address.town
          state = m.address.state
          postcode = m.address.postcode
          IdentityTijuana::Postcode.create(number: postcode, state: state)
          IdentityTijuana.fetch_user_updates(@sync_id) {}
          u.reload
          m.reload
          expect(u).to have_attributes(street_address: street_address, suburb: suburb)
          expect(u.postcode&.number).to eq(postcode)
          expect(u.postcode&.state).to eq(state)
          expect(m.address).to have_attributes(line1: street_address, town: suburb, state: state, postcode: postcode)
        end
      end
      context 'subscriptions' do
        it 'merges subscriptions to Identity if the most recent change was in Tijuana' do
          m = FactoryBot.create(:member)
          u = FactoryBot.create(:tijuana_user, email: m.email, is_member: true, do_not_call: false, do_not_sms: false)
          IdentityTijuana.fetch_user_updates(@sync_id) {}
          u.reload
          m.reload
          expect(u).to have_attributes(is_member: true, do_not_call: false, do_not_sms: false)
          expect(m.is_subscribed_to?(@email_sub)).to eq(true)
          expect(m.is_subscribed_to?(@calling_sub)).to eq(true)
          expect(m.is_subscribed_to?(@sms_sub)).to eq(true)
        end
        it 'merges unsubscriptions to Identity if the most recent change was in Tijuana' do
          m = FactoryBot.create(:member)
          MemberSubscription.create(subscription: @email_sub, member: m)
          MemberSubscription.create(subscription: @calling_sub, member: m)
          MemberSubscription.create(subscription: @sms_sub, member: m)
          u = FactoryBot.create(:tijuana_user, email: m.email, is_member: false, do_not_call: true, do_not_sms: true)
          IdentityTijuana.fetch_user_updates(@sync_id) {}
          u.reload
          m.reload
          expect(u).to have_attributes(is_member: false, do_not_call: true, do_not_sms: true)
          expect(m.is_subscribed_to?(@email_sub)).to eq(false)
          expect(m.is_subscribed_to?(@calling_sub)).to eq(false)
          expect(m.is_subscribed_to?(@sms_sub)).to eq(false)
        end
        it 'merges subscriptions to Tijuana if the most recent change was in Identity' do
          u = FactoryBot.create(:tijuana_user, is_member: false, do_not_call: true, do_not_sms: true)
          m = FactoryBot.create(:member, email: u.email)
          MemberSubscription.create(subscription: @email_sub, member: m)
          MemberSubscription.create(subscription: @calling_sub, member: m)
          MemberSubscription.create(subscription: @sms_sub, member: m)
          IdentityTijuana.fetch_user_updates(@sync_id) {}
          u.reload
          m.reload
          expect(u).to have_attributes(is_member: true, do_not_call: false, do_not_sms: false)
          expect(m.is_subscribed_to?(@email_sub)).to eq(true)
          expect(m.is_subscribed_to?(@calling_sub)).to eq(true)
          expect(m.is_subscribed_to?(@sms_sub)).to eq(true)
        end
        it 'merges unsubscriptions to Tijuana if the most recent change was in Identity' do
          u = FactoryBot.create(:tijuana_user, is_member: true, do_not_call: false, do_not_sms: false)
          m = FactoryBot.create(:member, email: u.email)
          IdentityTijuana.fetch_user_updates(@sync_id) {}
          u.reload
          m.reload
          expect(u).to have_attributes(is_member: false, do_not_call: true, do_not_sms: true)
          expect(m.is_subscribed_to?(@email_sub)).to eq(false)
          expect(m.is_subscribed_to?(@calling_sub)).to eq(false)
          expect(m.is_subscribed_to?(@sms_sub)).to eq(false)
        end
        it 'merges to a stable state when subscriptions in Identity cannot be represented in Tijuana' do
          u = FactoryBot.create(:tijuana_user, is_member: true, do_not_call: false, do_not_sms: false)
          m = FactoryBot.create(:member, email: u.email)
          MemberSubscription.create(subscription: @calling_sub, member: m)
          MemberSubscription.create(subscription: @sms_sub, member: m)
          IdentityTijuana.fetch_user_updates(@sync_id) {}
          u.reload
          m.reload
          expect(u).to have_attributes(is_member: false, do_not_call: false, do_not_sms: false)
          expect(m.is_subscribed_to?(@email_sub)).to eq(false)
          expect(m.is_subscribed_to?(@calling_sub)).to eq(false)
          expect(m.is_subscribed_to?(@sms_sub)).to eq(false)
          tj_updated_at = u.updated_at
          id_updated_at = m.updated_at
          IdentityTijuana.fetch_user_updates(@sync_id) {}
          u.reload
          m.reload
          expect(u.updated_at).to eq(tj_updated_at)
          expect(m.updated_at).to eq(id_updated_at)
        end
      end
      context 'custom field flags' do
        before(:each) do
          @deceased_custom_field_key = FactoryBot.create(:custom_field_key, name: 'deceased')
          @rts_custom_field_key = FactoryBot.create(:custom_field_key, name: 'rts')
          @deceased_tag = FactoryBot.create(:tijuana_tag, name: 'deceased')
          @rts_tag = FactoryBot.create(:tijuana_tag, name: 'rts')
        end
        it 'sets deceased and RTS flags in Identity if the most recent change was in Tijuana' do
          m = FactoryBot.create(:member)
          u = FactoryBot.create(:tijuana_user, email: m.email)
          FactoryBot.create(:tijuana_tagging, taggable_id: u.id, taggable_type: 'User', tag: @deceased_tag)
          FactoryBot.create(:tijuana_tagging, taggable_id: u.id, taggable_type: 'User', tag: @rts_tag)
          IdentityTijuana.fetch_user_updates(@sync_id) {}
          u.reload
          m.reload
          expect(u.taggings.find_by(tag: @deceased_tag)).not_to eq(nil)
          expect(u.taggings.find_by(tag: @rts_tag)).not_to eq(nil)
          expect(m.custom_fields.find_by(custom_field_key: @deceased_custom_field_key)&.data).to eq('true')
          expect(m.custom_fields.find_by(custom_field_key: @rts_custom_field_key)&.data).to eq('true')
        end
        it 'unsets deceased and RTS flags in Identity if the most recent change was in Tijuana' do
          m = FactoryBot.create(:member)
          FactoryBot.create(:custom_field, member: m, custom_field_key: @deceased_custom_field_key, data: 'true')
          FactoryBot.create(:custom_field, member: m, custom_field_key: @rts_custom_field_key, data: 'true')
          u = FactoryBot.create(:tijuana_user, email: m.email)
          IdentityTijuana.fetch_user_updates(@sync_id) {}
          u.reload
          m.reload
          expect(u.taggings.find_by(tag: @deceased_tag)).to eq(nil)
          expect(u.taggings.find_by(tag: @rts_tag)).to eq(nil)
          expect(m.custom_fields.find_by(custom_field_key: @deceased_custom_field_key)&.data).to eq('false')
          expect(m.custom_fields.find_by(custom_field_key: @rts_custom_field_key)&.data).to eq('false')
        end
        it 'sets deceased and RTS tags in Tijuana if the most recent change was in Identity' do
          u = FactoryBot.create(:tijuana_user)
          m = FactoryBot.create(:member, email: u.email)
          FactoryBot.create(:custom_field, member: m, custom_field_key: @deceased_custom_field_key, data: 'true')
          FactoryBot.create(:custom_field, member: m, custom_field_key: @rts_custom_field_key, data: 'true')
          IdentityTijuana.fetch_user_updates(@sync_id) {}
          u.reload
          m.reload
          expect(u.taggings.find_by(tag: @deceased_tag)).not_to eq(nil)
          expect(u.taggings.find_by(tag: @rts_tag)).not_to eq(nil)
          expect(m.custom_fields.find_by(custom_field_key: @deceased_custom_field_key)&.data).to eq('true')
          expect(m.custom_fields.find_by(custom_field_key: @rts_custom_field_key)&.data).to eq('true')
        end
        it 'unsets deceased and RTS tags in Tijuana if the most recent change was in Identity' do
          u = FactoryBot.create(:tijuana_user)
          FactoryBot.create(:tijuana_tagging, taggable_id: u.id, taggable_type: 'User', tag: @deceased_tag)
          FactoryBot.create(:tijuana_tagging, taggable_id: u.id, taggable_type: 'User', tag: @rts_tag)
          m = FactoryBot.create(:member, email: u.email)
          FactoryBot.create(:custom_field, member: m, custom_field_key: @deceased_custom_field_key, data: 'false')
          FactoryBot.create(:custom_field, member: m, custom_field_key: @rts_custom_field_key, data: 'false')
          IdentityTijuana.fetch_user_updates(@sync_id) {}
          u.reload
          m.reload
          expect(u.taggings.find_by(tag: @deceased_tag)).to eq(nil)
          expect(u.taggings.find_by(tag: @rts_tag)).to eq(nil)
          expect(m.custom_fields.find_by(custom_field_key: @deceased_custom_field_key)&.data).to eq('false')
          expect(m.custom_fields.find_by(custom_field_key: @rts_custom_field_key)&.data).to eq('false')
        end
      end
    end

    context 'when updating' do
      it 'updates members in Identity with changes in Tijuana' do
        u = FactoryBot.create(:tijuana_user_with_the_lot)
        IdentityTijuana.fetch_user_updates(@sync_id) {}
        m = Member.find_by(email: u.email)
        new_first_name = Faker::Name.first_name
        new_last_name = Faker::Name.last_name
        new_email = Faker::Internet.email
        # XXX syncing email changes from TJ to Id was disabled as of
        # e133c1d06fda1ee025a8242bc39692b3fa52ee54, so add this to
        # keep the test working otherwise for now:
        new_email = u.email
        new_home_number = "612#{::Kernel.rand(10_000_000..99_999_999)}"
        new_mobile_number = "614#{::Kernel.rand(10_000_000..99_999_999)}"
        new_street_address = Faker::Address.street_address
        new_suburb = Faker::Address.city
        new_postcode = IdentityTijuana::Postcode.new(number: Faker::Address.zip_code, state: Faker::Address.state_abbr)
        u.first_name = new_first_name
        u.last_name = new_last_name
        u.email = new_email
        u.home_number = new_home_number
        u.mobile_number = new_mobile_number
        u.street_address = new_street_address
        u.suburb = new_suburb
        u.postcode = new_postcode
        u.save
        IdentityTijuana.fetch_user_updates(@sync_id) {}
        u.reload
        m.reload
        expect(m).to have_attributes(first_name: new_first_name, last_name: new_last_name, email: new_email)
        expect(phone_numbers_are_equivalent(m.phone_numbers.mobile.first&.phone, new_mobile_number)).to eq(true)
        expect(phone_numbers_are_equivalent(m.phone_numbers.landline.first&.phone, new_home_number)).to eq(true)
        expect(m.address).to have_attributes(line1: new_street_address, town: new_suburb,
                                             state: new_postcode.state, postcode: new_postcode.number)
      end
      it 'updates users in Tijuana with changes in Identity' do
        m = FactoryBot.create(:member_with_the_lot)
        IdentityTijuana::Postcode.create(number: m.address.postcode, state: m.address.state)
        IdentityTijuana.fetch_user_updates(@sync_id) {}
        u = User.find_by(email: m.email)
        new_first_name = Faker::Name.first_name
        new_last_name = Faker::Name.last_name
        new_email = Faker::Internet.email
        m.first_name = new_first_name
        m.last_name = new_last_name
        m.email = new_email
        m.save
        new_mobile_number = FactoryBot.create(:mobile_number, member: m)
        new_landline_number = FactoryBot.create(:landline_number, member: m)
        new_address = FactoryBot.create(:address, member: m)
        IdentityTijuana::Postcode.create(number: new_address.postcode, state: new_address.state)
        IdentityTijuana.fetch_user_updates(@sync_id) {}
        u.reload
        m.reload
        expect(u).to have_attributes(email: new_email, first_name: new_first_name, last_name: new_last_name)
        expect(u).to have_attributes(street_address: new_address.line1, suburb: new_address.town)
        expect(u).to have_attributes(mobile_number: new_mobile_number.phone)
        expect(u).to have_attributes(home_number: new_landline_number.phone)
        expect(u.postcode.number).to eq(new_address.postcode)
        expect(u.postcode.state).to eq(new_address.state)
      end
    end

    it 'does not upsert members based on phone' do
      allow(Settings).to receive_message_chain(:options, :default_mobile_phone_national_destination_code).and_return(4)
      member = FactoryBot.create(:member)
      name = member.name
      member.update_phone_number('61427700300')

      FactoryBot.create(:tijuana_user, mobile_number: '41427700300', email: '')

      IdentityTijuana.fetch_user_updates(@sync_id) {}

      expect(Member.find_by_phone('61427700300')).to have_attributes(name: name)
      expect(Member.count).to eq(2)
    end
  end

  context '#fetch_tagging_updates' do
    before(:each) do
      reef_user = FactoryBot.create(:tijuana_user)
      econoreef_user = FactoryBot.create(:tijuana_user)
      economy_user = FactoryBot.create(:tijuana_user)
      non_user = FactoryBot.create(:tijuana_user)

      reef_tag = FactoryBot.create(:tijuana_tag, name: 'reef_syncid')
      economy_tag = FactoryBot.create(:tijuana_tag, name: 'economy_syncid')
      non_sync_tag = FactoryBot.create(:tijuana_tag, name: 'bees')

      FactoryBot.create(:tijuana_tagging, taggable_id: reef_user.id, taggable_type: 'User', tag: reef_tag)
      FactoryBot.create(:tijuana_tagging, taggable_id: econoreef_user.id, taggable_type: 'User', tag: reef_tag)
      FactoryBot.create(:tijuana_tagging, taggable_id: econoreef_user.id, taggable_type: 'User', tag: economy_tag)
      FactoryBot.create(:tijuana_tagging, taggable_id: economy_user.id, taggable_type: 'User', tag: economy_tag)
      FactoryBot.create(:tijuana_tagging, taggable_id: non_user.id, taggable_type: 'User', tag: non_sync_tag)

      #4.times { FactoryBot.create(:list) }
    end

    it 'imports no taggings if user dependent data cutoff is before taggings updated_at' do
      allow(Settings).to receive_message_chain("options.use_redshift") { false }
      allow(Settings).to receive_message_chain("options.allow_subscribe_via_upsert_member") { false }
      IdentityTijuana.fetch_user_updates(@sync_id) {}
      Sidekiq.redis { |r| r.set 'tijuana:users:dependent_data_cutoff', Date.today - 2 }
      IdentityTijuana.fetch_tagging_updates(@sync_id) {}

      expect(List.count).to eq(0)
    end

    it 'imports taggings if created_at not set' do
      allow(Settings).to receive_message_chain("options.use_redshift") { false }
      allow(Settings).to receive_message_chain("options.allow_subscribe_via_upsert_member") { false }
      IdentityTijuana::Tagging.all.update_all(created_at: nil)
      IdentityTijuana.fetch_user_updates(@sync_id) {}
      Sidekiq.redis { |r| r.set 'tijuana:users:dependent_data_cutoff', Date.today - 2 }

      IdentityTijuana.fetch_tagging_updates(@sync_id) {}

      expect(List.count).to eq(2)
      expect(Member.count).to eq(4)
    end

    it 'imports tags' do
      allow(Settings).to receive_message_chain("options.use_redshift") { false }
      allow(Settings).to receive_message_chain("options.allow_subscribe_via_upsert_member") { false }
      IdentityTijuana.fetch_user_updates(@sync_id) {}
      Sidekiq.redis { |r| r.set 'tijuana:users:dependent_data_cutoff', Date.today + 2 }

      IdentityTijuana.fetch_tagging_updates(@sync_id) {}

      reef_tag = List.find_by(name: 'TIJUANA TAG: reef_syncid')
      economy_tag = List.find_by(name: 'TIJUANA TAG: economy_syncid')
      non_sync_tag = List.find_by(name: 'TIJUANA TAG: bees')

      expect(reef_tag).not_to be_nil
      expect(economy_tag).not_to be_nil
      expect(non_sync_tag).to be_nil

      # Member count has been calculated and is correct
      expect(reef_tag.member_count).to eq(2)
      expect(economy_tag.member_count).to eq(2)

      expect(Member.count).to eq(4)
    end
  end
end
