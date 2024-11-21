require 'rails_helper'

describe IdentityTijuana::MemberSync do
  before(:each) do
    allow(Settings).to receive_message_chain("tijuana.email_subscription_id") {
      Subscription::EMAIL_SUBSCRIPTION.id
    }
    allow(Settings).to receive_message_chain("tijuana.calling_subscription_id") {
      Subscription::CALLING_SUBSCRIPTION.id
    }
    allow(Settings).to receive_message_chain("tijuana.sms_subscription_id") {
      Subscription::SMS_SUBSCRIPTION.id
    }
    allow(Settings).to(
      receive_message_chain("options.use_redshift") { false }
    )
    allow(Settings).to(
      receive_message_chain("options.allow_subscribe_via_upsert_member") { true }
    )
    allow(Settings).to(
      receive_message_chain("options.default_member_opt_in_subscriptions") { true }
    )
    allow(Settings).to(
      receive_message_chain("options.default_phone_country_code") { '61' }
    )
    allow(Settings).to(
      receive_message_chain("options.default_mobile_phone_national_destination_code") { 4 }
    )
    allow(Settings).to(
      receive_message_chain("options.lookup_phone_type_on_create") { true }
    )
    allow(Settings).to(
      receive_message_chain("geography.postcode_dash") { false }
    )
    allow(Settings).to(
      receive_message_chain("geography.area_lookup.track_area_probabilities") { false }
    )
  end

  context '#find_primary_user_for_member' do
    context 'member with a single linked user' do
      it 'should match identical emails' do
        m = FactoryBot.create(:member, email: 'alice@example.com')
        u = FactoryBot.create(:tijuana_user, email: m.email)
        MemberExternalId.create!(
          system: 'tijuana',
          member: m,
          external_id: u.id.to_s
        )

        expect(
          IdentityTijuana::MemberSync.find_primary_user_for_member(m)
        ).to eq(u)
      end

      it 'should match different emails' do
        m = FactoryBot.create(:member, email: 'alice@example.com')
        u = FactoryBot.create(:tijuana_user, email: 'bob@example.com')
        MemberExternalId.create!(
          system: 'tijuana',
          member: m,
          external_id: u.id.to_s
        )

        expect(
          IdentityTijuana::MemberSync.find_primary_user_for_member(m)
        ).to eq(u)
      end
    end

    context 'member with multiple linked users' do
      it 'should match identical emails' do
        m = FactoryBot.create(:member, email: 'alice@example.com')
        # Create the matching user last to ensure ordering does not
        # effect the result
        u1 = FactoryBot.create(:tijuana_user, email: 'bob@example.com')
        MemberExternalId.create!(
          system: 'tijuana',
          member: m,
          external_id: u1.id.to_s
        )
        u2 = FactoryBot.create(:tijuana_user, email: 'alice@example.com')
        MemberExternalId.create!(
          system: 'tijuana',
          member: m,
          external_id: u2.id.to_s
        )

        expect(
          IdentityTijuana::MemberSync.find_primary_user_for_member(m)
        ).to eq(u2)
      end

      it 'should match de-normalised emails' do
        m = FactoryBot.create(:member, email: 'alice@example.com')
        # Create the matching user last to ensure ordering does not
        # effect the result
        u1 = FactoryBot.create(:tijuana_user, email: 'bob@example.com')
        MemberExternalId.create!(
          system: 'tijuana',
          member: m,
          external_id: u1.id.to_s
        )
        u2 = FactoryBot.create(:tijuana_user, email: '  Alice@example  .com  ')
        MemberExternalId.create!(
          system: 'tijuana',
          member: m,
          external_id: u2.id.to_s
        )

        expect(
          IdentityTijuana::MemberSync.find_primary_user_for_member(m)
        ).to eq(u2)
      end

      it 'should not match typo emails' do
        m = FactoryBot.create(:member, email: 'alice@gmail.com')
        # Create the matching user last to ensure ordering does not
        # effect the result
        u1 = FactoryBot.create(:tijuana_user, email: 'alice@gmail.co')
        MemberExternalId.create!(
          system: 'tijuana',
          member: m,
          external_id: u1.id.to_s
        )
        u2 = FactoryBot.create(:tijuana_user, email: 'alice@gmail.com')
        MemberExternalId.create!(
          system: 'tijuana',
          member: m,
          external_id: u2.id.to_s
        )

        expect(
          IdentityTijuana::MemberSync.find_primary_user_for_member(m)
        ).to eq(u2)
      end

      it 'should fallback to subscription status emails' do
        m = FactoryBot.create(:member, email: 'alice@example.com')
        # Create the matching user last to ensure ordering does not
        # effect the result
        u1 = FactoryBot.create(
          :tijuana_user,
          email: 'bob@example.com',
          is_member: false
        )
        MemberExternalId.create!(
          system: 'tijuana',
          member: m,
          external_id: u1.id.to_s
        )
        u2 = FactoryBot.create(
          :tijuana_user,
          email: 'charlie@example.com',
          is_member: true
        )
        MemberExternalId.create!(
          system: 'tijuana',
          member: m,
          external_id: u2.id.to_s
        )
        u3 = FactoryBot.create(
          :tijuana_user,
          email: 'dan@example.com',
          is_member: true
        )
        MemberExternalId.create!(
          system: 'tijuana',
          member: m,
          external_id: u3.id.to_s
        )

        expect(
          IdentityTijuana::MemberSync.find_primary_user_for_member(m)
        ).to eq(u2)
      end

      it 'should fall back to created at' do
        m = FactoryBot.create(:member, email: 'alice@example.com')

        u1 = FactoryBot.create(
          :tijuana_user,
          email: 'bob@example.com',
          created_at: 1.minute.ago,
          is_member: false
        )
        MemberExternalId.create!(
          system: 'tijuana',
          member: m,
          external_id: u1.id.to_s
        )

        u2 = FactoryBot.create(
          :tijuana_user,
          email: 'charlie@example.com',
          created_at: 10.minutes.ago,
          is_member: false
        )
        MemberExternalId.create!(
          system: 'tijuana',
          member: m,
          external_id: u2.id.to_s
        )

        expect(
          IdentityTijuana::MemberSync.find_primary_user_for_member(m)
        ).to eq(u2)
      end
    end
  end

  context '#export_member' do
    it 'creates a new TJ user when no matching user found' do
      m = FactoryBot.create(:member)

      IdentityTijuana::MemberSync.export_member(m, 0)

      expect(User.first).to have_attributes(email: m.email)
      expect(m.get_external_ids('tijuana').count).to eq(1)
      expect(m.get_external_ids('tijuana').first)
        .to eq(User.first.id.to_s)
    end

    it 'links an existing TJ user when found' do
      m = FactoryBot.create(:member)
      FactoryBot.create(:tijuana_user, email: m.email)

      IdentityTijuana::MemberSync.export_member(m, 0)

      expect(User.first).to have_attributes(email: m.email)
      expect(m.get_external_ids('tijuana').count).to eq(1)
      expect(m.get_external_ids('tijuana').first)
        .to eq(User.first.id.to_s)
    end

    it 'updates an existing linked TJ user' do
      u = FactoryBot.create(:tijuana_user, first_name: 'Alice')
      m = FactoryBot.create(:member, email: u.email, first_name: 'Bob')
      MemberExternalId.create!(
        system: 'tijuana', member: m, external_id: u.id.to_s
      )

      IdentityTijuana::MemberSync.export_member(m, 0)

      expect(User.first).to have_attributes(first_name: m.first_name)
      expect(m.get_external_ids('tijuana').count).to eq(1)
    end

    it 'uses the primary linked user when many are present' do
      u1 = FactoryBot.create(
        :tijuana_user,
        email: 'alice@example.com',
        first_name: 'Alice'
      )
      u2 = FactoryBot.create(
        :tijuana_user,
        email: 'bob@example.com',
        first_name: 'Bob'
      )
      m = FactoryBot.create(:member, email: u2.email, first_name: 'Charlie')
      MemberExternalId.create!(
        system: 'tijuana', member: m, external_id: u1.id.to_s
      )
      MemberExternalId.create!(
        system: 'tijuana', member: m, external_id: u2.id.to_s
      )

      IdentityTijuana::MemberSync.export_member(m, 0)

      expect(User.second).to have_attributes(first_name: 'Charlie')
      expect(m.get_external_ids('tijuana').count).to eq(2)
    end

    it 'removes all dangling external ids' do
      u = FactoryBot.create(:tijuana_user, first_name: 'Alice')
      m = FactoryBot.create(:member, email: u.email, first_name: 'Bob')
      MemberExternalId.create!(
        system: 'tijuana', member: m, external_id: (u.id + 1).to_s
      )
      MemberExternalId.create!(
        system: 'tijuana', member: m, external_id: u.id.to_s
      )

      IdentityTijuana::MemberSync.export_member(m, 0)

      expect(User.first).to have_attributes(first_name: 'Bob')
      expect(m.get_external_ids('tijuana').count).to eq(1)
    end
  end

  context '#import_user' do
    it 'creates a new Id member when no matching member is found' do
      u = FactoryBot.create(:tijuana_user)

      IdentityTijuana::MemberSync.import_user(u.id, 0)

      expect(Member.first).to have_attributes(email: u.email)
      expect(Member.first.get_external_ids('tijuana').count).to eq(1)
      expect(Member.first.get_external_ids('tijuana').first)
        .to eq(u.id.to_s)
    end

    it 'links an existing TJ user when found' do
      u = FactoryBot.create(:tijuana_user)
      FactoryBot.create(:member, email: u.email)

      IdentityTijuana::MemberSync.import_user(u.id, 0)

      expect(Member.first).to have_attributes(email: u.email)
      expect(Member.first.get_external_ids('tijuana').count).to eq(1)
      expect(Member.first.get_external_ids('tijuana').first)
        .to eq(u.id.to_s)
    end

    it 'updates an existing linked TJ user' do
      m = FactoryBot.create(:member, first_name: 'Alice')
      u = FactoryBot.create(:tijuana_user, email: m.email, first_name: 'Bob')
      MemberExternalId.create!(
        system: 'tijuana', member: m, external_id: u.id.to_s
      )

      IdentityTijuana::MemberSync.import_user(u.id, 0)

      expect(Member.first).to have_attributes(first_name: u.first_name)
      expect(Member.first.get_external_ids('tijuana').count).to eq(1)
    end

    it 'skips syncing when linked, but not the primary linked user' do
      m = FactoryBot.create(:member)
      u1 = FactoryBot.create(
        :tijuana_user,
        email: 'alice@example.com',
        first_name: 'Alice'
      )
      u2 = FactoryBot.create(
        :tijuana_user,
        email: m.email,
        first_name: m.first_name
      )
      MemberExternalId.create!(
        system: 'tijuana', member: m, external_id: u1.id.to_s
      )
      MemberExternalId.create!(
        system: 'tijuana', member: m, external_id: u2.id.to_s
      )

      IdentityTijuana::MemberSync.import_user(u1.id, 0)

      expect(Member.first).to have_attributes(first_name: u2.first_name)
      expect(Member.first.get_external_ids('tijuana').count).to eq(2)
    end

    it 'skips syncing when not linked and not the primary linked user' do
      # This is effectively checking that if a member typo's their
      # email address in a way that the Cleanser picks up the typo and
      # corrects it, and the corrected email points to an existing
      # user, that the typo'ed user is not sync'ed (since it's not the
      # primary).
      m = FactoryBot.create(:member, email: 'alice@gmail.com', first_name: 'Alice')
      u1 = FactoryBot.create(
        :tijuana_user,
        email: 'alice@gmial.com',
        first_name: 'AL1c3'
      )
      u2 = FactoryBot.create(
        :tijuana_user,
        email: m.email,
        first_name: m.first_name
      )
      MemberExternalId.create!(
        system: 'tijuana', member: m, external_id: u2.id.to_s
      )

      IdentityTijuana::MemberSync.import_user(u1.id, 0)

      expect(Member.first)
        .to have_attributes(first_name: u2.first_name)
      expect(Member.first.get_external_ids('tijuana').sort)
        .to eq([u1.id.to_s, u2.id.to_s])
    end
  end
end
