require 'rails_helper'

describe IdentityTijuana do
  before(:all) do
    @sync_id = 1
    Sidekiq::Testing.inline!
  end

  before(:each) do
    @email_sub = Subscription::EMAIL_SUBSCRIPTION
    @calling_sub = Subscription::CALLING_SUBSCRIPTION
    @sms_sub = Subscription::SMS_SUBSCRIPTION
    allow(Settings).to(
      receive_message_chain("tijuana.database_url") { ENV['TIJUANA_DATABASE_URL'] }
    )
    allow(Settings).to receive_message_chain("tijuana.email_subscription_id") { @email_sub.id }
    allow(Settings).to receive_message_chain("tijuana.calling_subscription_id") { @calling_sub.id }
    allow(Settings).to receive_message_chain("tijuana.sms_subscription_id") { @sms_sub.id }
    allow(Settings).to receive_message_chain("tijuana.pull_batch_amount") { nil }
    allow(Settings).to receive_message_chain("tijuana.push_batch_amount") { nil }

    allow(Settings).to receive_message_chain("options.use_redshift") { false }
    allow(Settings).to receive_message_chain("options.allow_subscribe_via_upsert_member") { true }
    allow(Settings).to receive_message_chain("options.default_member_opt_in_subscriptions") { true }
    allow(Settings).to receive_message_chain("options.default_phone_country_code") { '61' }
    allow(Settings).to receive_message_chain("options.default_mobile_phone_national_destination_code") { 4 }
    allow(Settings).to receive_message_chain("options.lookup_phone_type_on_create") { true }

    allow(Settings).to receive_message_chain("geography.postcode_dash") { false }
    allow(Settings).to receive_message_chain("geography.area_lookup.track_area_probabilities") { false }
  end

  def phone_numbers_are_equivalent(phone1, phone2)
    # Compare only the last 8 digits to sidestep issues with formatting of the prefix.
    ph1 = phone1 ? phone1[-8..-1] || phone1 : nil
    ph2 = phone2 ? phone2[-8..-1] || phone2 : nil
    ph1 == ph2
  end

  context '#pull' do
    before(:each) do
      @external_system_params = JSON.generate({ 'pull_job' => 'fetch_user_updates' })
    end

    context 'with valid parameters' do
      it 'should call the corresponding method' do
        expect(IdentityTijuana).to receive(:fetch_user_updates).exactly(1).times.with(1)
        IdentityTijuana.pull(@sync_id, @external_system_params)
      end
    end
  end

  context '#fetch_user_updates' do
    before(:each) do
      @email_sub = Subscription::EMAIL_SUBSCRIPTION
      @calling_sub = Subscription::CALLING_SUBSCRIPTION
      @sms_sub = Subscription::SMS_SUBSCRIPTION
    end

    context 'when creating' do
      it 'creates new members in Identity' do
        u = FactoryBot.create(:tijuana_user_with_the_lot)
        IdentityTijuana.fetch_user_updates(@sync_id) {
          # pass
        }
        m = Member.find_by(email: u.email)
        expect(m).to have_attributes(first_name: u.first_name, last_name: u.last_name)
        expect(phone_numbers_are_equivalent(m.phone_numbers.mobile.first&.phone, u.mobile_number)).to eq(true)
        expect(phone_numbers_are_equivalent(m.phone_numbers.landline.first&.phone, u.home_number)).to eq(true)
        expect(m.address).to have_attributes(line1: u.street_address, town: u.suburb,
                                             state: u.postcode.state, postcode: u.postcode.number)
      end
      it 'creates new users in Tijuana' do
        m = FactoryBot.create(:member_with_the_lot)
        IdentityTijuana::Postcode.create!(number: m.address.postcode, state: m.address.state)
        IdentityTijuana.fetch_user_updates(@sync_id) {
          # pass
        }
        u = User.find_by(email: m.email)
        expect(u).to have_attributes(first_name: m.first_name, last_name: m.last_name)
        expect(u).to have_attributes(street_address: m.address.line1, suburb: m.address.town)
        expect(u.postcode.number).to eq(m.address.postcode)
        expect(u.postcode.state).to eq(m.address.state)
      end
      it 'creates new users in Tijuana without postcode' do
        m = FactoryBot.create(:member_with_the_lot)
        m.addresses.create!({ postcode: "invalid" })
        IdentityTijuana.fetch_user_updates(@sync_id) {
          # pass
        }
        u = User.find_by(email: m.email)
        expect(u).to have_attributes(first_name: m.first_name, last_name: m.last_name)
        expect(u).to have_attributes(street_address: m.address.line1, suburb: m.address.town)
        expect(u.postcode).to be_nil
      end
    end

    context 'when merging' do
      context 'names' do
        it 'merges a missing name to Identity' do
          u = FactoryBot.create(:tijuana_user)
          m = FactoryBot.create(:member, email: u.email, first_name: nil, middle_names: nil, last_name: nil)
          first_name = u.first_name
          last_name = u.last_name
          IdentityTijuana.fetch_user_updates(@sync_id) {
            # pass
          }
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
          IdentityTijuana.fetch_user_updates(@sync_id) {
            # pass
          }
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
          IdentityTijuana.fetch_user_updates(@sync_id) {
            # pass
          }
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
          IdentityTijuana.fetch_user_updates(@sync_id) {
            # pass
          }
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
          IdentityTijuana.fetch_user_updates(@sync_id) {
            # pass
          }
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
          IdentityTijuana.fetch_user_updates(@sync_id) {
            # pass
          }
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
          IdentityTijuana.fetch_user_updates(@sync_id) {
            # pass
          }
          u.reload
          m.reload
          expect(u).to have_attributes(mobile_number: mobile_number)
          expect(phone_numbers_are_equivalent(mobile_number, m.phone_numbers.mobile.first&.phone)).to eq(true)
        end
        it 'merges a missing mobile number to Tijuana' do
          m = FactoryBot.create(:member_with_mobile)
          u = FactoryBot.create(:tijuana_user, email: m.email)
          mobile_number = m.phone_numbers.mobile.first&.phone
          IdentityTijuana.fetch_user_updates(@sync_id) {
            # pass
          }
          u.reload
          m.reload
          expect(phone_numbers_are_equivalent(mobile_number, u.mobile_number)).to eq(true)
          expect(m.phone_numbers.mobile.first&.phone).to eq(mobile_number)
        end
        it 'merges a conflicting mobile number to Identity if the most recent change was in Tijuana' do
          m = FactoryBot.create(:member_with_mobile)
          u = FactoryBot.create(:tijuana_user_with_mobile_number, email: m.email)
          mobile_number = u.mobile_number
          IdentityTijuana.fetch_user_updates(@sync_id) {
            # pass
          }
          u.reload
          m.reload
          expect(u).to have_attributes(mobile_number: mobile_number)
          expect(phone_numbers_are_equivalent(mobile_number, m.phone_numbers.mobile.first&.phone)).to eq(true)
        end
        it 'merges a conflicting mobile number to Tijuana if the most recent change was in Identity' do
          u = FactoryBot.create(:tijuana_user_with_mobile_number)
          m = FactoryBot.create(:member_with_mobile, email: u.email)
          mobile_number = m.phone_numbers.mobile.first&.phone
          IdentityTijuana.fetch_user_updates(@sync_id) {
            # pass
          }
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
          IdentityTijuana.fetch_user_updates(@sync_id) {
            # pass
          }
          u.reload
          m.reload
          expect(u).to have_attributes(home_number: landline_number)
          expect(phone_numbers_are_equivalent(landline_number, m.phone_numbers.landline.first&.phone)).to eq(true)
        end
        it 'merges a missing landline number to Tijuana' do
          m = FactoryBot.create(:member_with_landline)
          u = FactoryBot.create(:tijuana_user, email: m.email)
          landline_number = m.phone_numbers.landline.first&.phone
          IdentityTijuana.fetch_user_updates(@sync_id) {
            # pass
          }
          u.reload
          m.reload
          expect(phone_numbers_are_equivalent(landline_number, u.home_number)).to eq(true)
          expect(m.phone_numbers.landline.first&.phone).to eq(landline_number)
        end
        it 'merges a conflicting landline number to Identity if the most recent change was in Tijuana' do
          m = FactoryBot.create(:member_with_landline)
          u = FactoryBot.create(:tijuana_user_with_home_number, email: m.email)
          landline_number = u.home_number
          IdentityTijuana.fetch_user_updates(@sync_id) {
            # pass
          }
          u.reload
          m.reload
          expect(u).to have_attributes(home_number: landline_number)
          expect(phone_numbers_are_equivalent(landline_number, m.phone_numbers.landline.first&.phone)).to eq(true)
        end
        it 'merges a conflicting landline number to Tijuana if the most recent change was in Identity' do
          u = FactoryBot.create(:tijuana_user_with_home_number)
          m = FactoryBot.create(:member_with_landline, email: u.email)
          landline_number = m.phone_numbers.landline.first&.phone
          IdentityTijuana.fetch_user_updates(@sync_id) {
            # pass
          }
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
          IdentityTijuana.fetch_user_updates(@sync_id) {
            # pass
          }
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
          IdentityTijuana::Postcode.create!(number: postcode, state: state)
          IdentityTijuana.fetch_user_updates(@sync_id) {
            # pass
          }
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
          IdentityTijuana.fetch_user_updates(@sync_id) {
            # pass
          }
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
          p = IdentityTijuana::Postcode.create!(number: postcode, state: state)
          u.postcode = p
          IdentityTijuana.fetch_user_updates(@sync_id) {
            # pass
          }
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
          IdentityTijuana.fetch_user_updates(@sync_id) {
            # pass
          }
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
          IdentityTijuana::Postcode.create!(number: postcode, state: state)
          IdentityTijuana.fetch_user_updates(@sync_id) {
            # pass
          }
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
          IdentityTijuana.fetch_user_updates(@sync_id) {
            # pass
          }
          u.reload
          m.reload
          expect(u).to have_attributes(is_member: true, do_not_call: false, do_not_sms: false)
          expect(m.is_subscribed_to?(@email_sub)).to eq(true)
          expect(m.is_subscribed_to?(@calling_sub)).to eq(true)
          expect(m.is_subscribed_to?(@sms_sub)).to eq(true)
        end
        it 'merges unsubscriptions to Identity if the most recent change was in Tijuana' do
          m = FactoryBot.create(:member)
          MemberSubscription.create!(subscription: @email_sub, member: m)
          MemberSubscription.create!(subscription: @calling_sub, member: m)
          MemberSubscription.create!(subscription: @sms_sub, member: m)
          u = FactoryBot.create(:tijuana_user, email: m.email, is_member: false, do_not_call: true, do_not_sms: true)
          IdentityTijuana.fetch_user_updates(@sync_id) {
            # pass
          }
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
          MemberSubscription.create!(subscription: @email_sub, member: m)
          MemberSubscription.create!(subscription: @calling_sub, member: m)
          MemberSubscription.create!(subscription: @sms_sub, member: m)
          IdentityTijuana.fetch_user_updates(@sync_id) {
            # pass
          }
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
          IdentityTijuana.fetch_user_updates(@sync_id) {
            # pass
          }
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
          MemberSubscription.create!(subscription: @calling_sub, member: m)
          MemberSubscription.create!(subscription: @sms_sub, member: m)
          IdentityTijuana.fetch_user_updates(@sync_id) {
            # pass
          }
          u.reload
          m.reload
          expect(u).to have_attributes(is_member: false, do_not_call: false, do_not_sms: false)
          expect(m.is_subscribed_to?(@email_sub)).to eq(false)
          expect(m.is_subscribed_to?(@calling_sub)).to eq(false)
          expect(m.is_subscribed_to?(@sms_sub)).to eq(false)
          tj_updated_at = u.updated_at
          id_updated_at = m.updated_at
          IdentityTijuana.fetch_user_updates(@sync_id) {
            # pass
          }
          u.reload
          m.reload
          expect(u.updated_at).to eq(tj_updated_at)
          expect(m.updated_at).to eq(id_updated_at)
        end
      end
    end

    context 'when updating' do
      it 'updates members in Identity with changes in Tijuana' do
        u = FactoryBot.create(:tijuana_user_with_the_lot)
        IdentityTijuana.fetch_user_updates(@sync_id) {
          # pass
        }
        m = Member.find_by(email: u.email)
        new_first_name = Faker::Name.first_name
        new_last_name = Faker::Name.last_name
        Faker::Internet.email
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
        u.save!
        IdentityTijuana.fetch_user_updates(@sync_id) {
          # pass
        }
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
        IdentityTijuana::Postcode.create!(number: m.address.postcode, state: m.address.state)
        IdentityTijuana.fetch_user_updates(@sync_id) {
          # pass
        }
        u = User.find_by(email: m.email)
        new_first_name = Faker::Name.first_name
        new_last_name = Faker::Name.last_name
        new_email = Faker::Internet.email
        m.first_name = new_first_name
        m.last_name = new_last_name
        m.email = new_email
        m.save!
        new_mobile_number = FactoryBot.create(:mobile_number, member: m)
        new_landline_number = FactoryBot.create(:landline_number, member: m)
        new_address = FactoryBot.create(:address, member: m)
        IdentityTijuana::Postcode.create!(number: new_address.postcode, state: new_address.state)
        IdentityTijuana.fetch_user_updates(@sync_id) {
          # pass
        }
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
      member = FactoryBot.create(:member)
      name = member.name
      member.update_phone_number('61427700300')

      FactoryBot.create(:tijuana_user, mobile_number: '41427700300', email: '')

      IdentityTijuana.fetch_user_updates(@sync_id) {
        # pass
      }

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

      # 4.times { FactoryBot.create(:list) }
    end

    it 'imports no taggings if user dependent data cutoff is before taggings updated_at' do
      Sidekiq.redis { |r| r.set 'tijuana:users:dependent_data_cutoff', 2.days.ago }
      IdentityTijuana.fetch_tagging_updates(@sync_id) {
        # pass
      }

      expect(List.count).to eq(0)
    end

    it 'imports taggings if created_at not set' do
      IdentityTijuana::Tagging.all { |t| t.update!(created_at: nil) }
      IdentityTijuana.fetch_user_updates(@sync_id) {
        # pass
      }
      Sidekiq.redis { |r| r.set 'tijuana:users:dependent_data_cutoff', 2.days.ago }

      IdentityTijuana.fetch_tagging_updates(@sync_id) {
        # pass
      }

      expect(List.count).to eq(2)
      expect(Member.count).to eq(4)
    end

    it 'imports tags' do
      IdentityTijuana.fetch_user_updates(@sync_id) {
        # pass
      }
      Sidekiq.redis { |r| r.set 'tijuana:users:dependent_data_cutoff', 2.days.ago }

      IdentityTijuana.fetch_tagging_updates(@sync_id) {
        # pass
      }

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

  context '#fetch_donation_updates' do
    before(:each) do
      @donations = []
      @regular_donations = []

      5.times do
        user = FactoryBot.create(:tijuana_user)
        donation = FactoryBot.create(
          :tijuana_donation,
          amount_in_cents: Faker::Number.between(from: 1000, to: 10_000),
          user: user,
          content_module_id: Faker::Number.between(from: 1, to: 5),
          payment_method: Faker::Finance.credit_card,
          frequency: %w[one_off weekly monthly yearly].sample,
          page_id: Faker::Number.between(from: 1, to: 5),
          cover_processing_fee: Faker::Boolean.boolean,
          created_at: Faker::Date.between(from: '2022-01-01',
                                          to: '2022-03-03`'),
          updated_at: Faker::Date.between(from: '2022-03-03',
                                          to: Time.zone.today - 2.days)
        )
        @donations << donation
        if donation.frequency != 'one_off'
          @regular_donations << donation
        end
      end

      100.times do
        donation = @donations.sample
        successful = Faker::Boolean.boolean
        updated_at = Faker::Date.between(
          from: donation.created_at,
          to: Time.zone.today - 2.days
        ).to_datetime

        transaction = FactoryBot.create(
          :tijuana_transaction,
          donation: donation,
          successful: successful,
          amount_in_cents: Faker::Number.between(from: 500, to: 5000),
          created_at: updated_at,
          updated_at: updated_at
        )

        # Create a refund for some transactions
        if successful && [true, false].sample
          FactoryBot.create(
            :tijuana_transaction,
            donation: donation,
            refund_of_id: transaction.id,
            successful: true,
            amount_in_cents: -transaction.amount_in_cents,
            created_at: transaction.created_at + 1.day,
            updated_at: transaction.updated_at + 1.day
          )
        end
      end
    end

    it 'upserts regular donations for non-one-off frequencies' do
      IdentityTijuana.fetch_user_updates(@sync_id) {
        # pass
      }

      Sidekiq.redis { |r|
        r.set 'tijuana:users:dependent_data_cutoff',
              2.days.ago
      }
      IdentityTijuana.fetch_donation_updates(@sync_id) {
        # pass
      }

      @regular_donations.each do |donation|
        regular_donation = Donations::RegularDonation.find_by(external_id: donation.id)
        member = Member.find_by_external_id(:tijuana, donation.user_id)
        expect(regular_donation).to be_present
        expect(regular_donation.member_id).to eq(member.id)
        expect(regular_donation.started_at).to eq(donation.created_at)
        expect(regular_donation.ended_at).to eq(donation.cancelled_at || (donation.active ? nil : donation.updated_at))
        expect(regular_donation.frequency).to eq(donation.frequency)
        expect(regular_donation.medium).to eq(donation.payment_method)
        expect(regular_donation.source).to eq('tijuana')
        expect(regular_donation.current_amount).to eq(donation.amount_in_cents / 100.0)
        expect(regular_donation.created_at).to eq(donation.created_at)
      end
    end

    it 'syncs successful transactions as donations' do
      IdentityTijuana.fetch_user_updates(@sync_id) {
        # pass
      }

      Sidekiq.redis { |r|
        r.set 'tijuana:users:dependent_data_cutoff',
              2.days.ago
      }
      IdentityTijuana.fetch_donation_updates(@sync_id) {
        # pass
      }

      total_donations_amount = Donations::Donation.sum(:amount)

      amounts_in_cents = IdentityTijuana::Transaction.where(successful: true)
                                                     .sum(:amount_in_cents)
                                                     .to_f

      expect(total_donations_amount).to eq(amounts_in_cents / 100)

      expect(Donations::Donation.count).to eq(
        IdentityTijuana::Transaction.where(successful: true).count
      )
    end

    it 'syncs refunds as negative donations and timestamps refunded donation with refunded_at' do
      IdentityTijuana.fetch_user_updates(@sync_id) {
        # pass
      }

      Sidekiq.redis { |r|
        r.set 'tijuana:users:dependent_data_cutoff',
              2.days.ago
      }
      IdentityTijuana.fetch_donation_updates(@sync_id) {
        # pass
      }
      total_donations_refund_amount = Donations::Donation
                                      .where
                                      .not(refunded_at: nil)
                                      .sum(:amount)
      total_donations_refund_count = Donations::Donation
                                     .where
                                     .not(refunded_at: nil)
                                     .count()

      total_transactions_refund_amount = IdentityTijuana::Transaction
                                         .where
                                         .not(refund_of_id: nil)
                                         .sum(:amount_in_cents)
      total_transactions_refund_count = IdentityTijuana::Transaction
                                        .where
                                        .not(refund_of_id: nil)
                                        .count()

      expect(total_donations_refund_amount.abs * 100).to eq(
        total_transactions_refund_amount.abs
      )
      expect(total_donations_refund_count).to eq(
        total_transactions_refund_count
      )
    end

    it 'syncs successful transactions with the same updated_at as donations' do
      selected_donations = @donations.sample(3)

      selected_donations.each do |donation|
        random_datetime = Faker::Date.between(
          from: donation.created_at, to: Time.zone.today - 2.days
        ).to_datetime

        rand(2..5).times do
          FactoryBot.create(:tijuana_transaction,
                            donation: donation,
                            successful: true,
                            amount_in_cents: Faker::Number.between(
                              from: 500,
                              to: 5000
                            ),
                            created_at: random_datetime,
                            updated_at: random_datetime)
        end
      end

      IdentityTijuana.fetch_user_updates(@sync_id) {
        # pass
      }

      Sidekiq.redis { |r| r.set 'tijuana:users:dependent_data_cutoff', 2.days.ago }
      IdentityTijuana.fetch_donation_updates(@sync_id) {
        # pass
      }

      total_donations_amount = Donations::Donation.sum(:amount)

      amounts_in_cents = IdentityTijuana::Transaction.where(successful: true)
                                                     .sum(:amount_in_cents)
                                                     .to_f

      expect(total_donations_amount).to eq(amounts_in_cents / 100)

      expect(Donations::Donation.count).to eq(
        IdentityTijuana::Transaction.where(successful: true).count
      )
    end
  end
end
