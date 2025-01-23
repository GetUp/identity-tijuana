RSpec.describe IdentityTijuana::MemberSync do
  describe '#get_id_change_date' do
    include ActiveSupport::Testing::TimeHelpers

    before(:each) do
      @email_sub = Subscription::EMAIL_SUBSCRIPTION
      @calling_sub = Subscription::CALLING_SUBSCRIPTION
      @sms_sub = Subscription::SMS_SUBSCRIPTION

      allow(Settings).to receive_message_chain(
        "options.default_phone_country_code"
      ) { '61' }
      allow(Settings).to receive_message_chain(
        "options.default_mobile_phone_national_destination_code"
      ) { 4 }
      allow(Settings).to receive_message_chain(
        "tijuana.email_subscription_id"
      ) { @email_sub.id }
      allow(Settings).to receive_message_chain(
        "tijuana.calling_subscription_id"
      ) { @calling_sub.id }
      allow(Settings).to receive_message_chain(
        "tijuana.sms_subscription_id"
      ) { @sms_sub.id }
      allow(Settings).to receive_message_chain(
        "geography.postcode_dash"
      ) { false }
      allow(Settings).to receive_message_chain(
        "geography.area_lookup.track_area_probabilities"
      ) { false }
    end

    context 'with multiple audit logs entries' do
      it 'correctly identifies the change date for name' do
        member = nil

        travel_to(2.minutes.ago) do
          member = FactoryBot.create(:member)
          member.update!(first_name: 'NewName')
        end

        travel_to(1.minute.ago) do
          member.update!(first_name: 'NewName')
        end

        last_audit_log_with_change = nil
        travel_to(30.seconds.ago) do
          member.update!(last_name: 'NewLastName')
          last_audit_log_with_change = member.audits.last
        end

        member.update!(last_name: 'NewLastName')

        # Get all audit logs and validate timestamps
        audit_logs = member.audits.where(auditable_type: 'Member')

        id_change_date = described_class.get_id_change_date(
          member, :name,
          member.updated_at
        )

        expect(id_change_date).to eq(last_audit_log_with_change.created_at)
          .or(eq(member.updated_at))
        expect(last_audit_log_with_change.audited_changes.key?('last_name'))
          .to be(true)
        expect(audit_logs.count).to eq(5)
      end

      it 'correctly identifies the change date for email' do
        member = nil

        travel_to(3.minutes.ago) do
          member = FactoryBot.create(:member)
          member.update!(email: 'rust@grom.com')
        end

        travel_to(2.minutes.ago) do
          member.update!(email: 'rust@grom.com')
        end

        last_audit_log_with_change = nil
        travel_to(1.minute.ago) do
          member.update!(email: 'go-rust@grom.com')
          last_audit_log_with_change = member.audits.where(
            auditable_type: 'Member',
          ).reorder(created_at: :desc).first
        end

        member.update!(email: 'go-rust@grom.com')

        audit_logs = member.audits.where(auditable_type: 'Member')

        id_change_date = described_class.get_id_change_date(member, :email,
                                                            member.updated_at)

        expect(id_change_date).to eq(member.updated_at)
          .or(eq(last_audit_log_with_change.created_at))
        expect(last_audit_log_with_change.audited_changes.key?('email'))
          .to be(true)
        expect(audit_logs.count).to eq(5)
      end

      it 'correctly identifies the change date for mobile' do
        member = nil

        travel_to(3.minutes.ago) do
          member = FactoryBot.create(:member)
          member.update_phone_number('0431 111 111')
        end

        travel_to(2.minutes.ago) do
          member.update_phone_number('0431 111 111')
        end

        last_audit_log_with_change = nil
        travel_to(1.minute.ago) do
          member.update_phone_number('61427700333')
          last_audit_log_with_change = member.associated_audits.where(
            auditable_type: 'PhoneNumber',
          ).reorder(created_at: :desc).first
        end

        member.update_phone_number('61427700333')
        member.phone_numbers.reload

        # NB: we'll only have `2` audits as `update_phone_number`
        # will simply return if the new phone number is same
        # as the existing one.
        audit_logs = member.associated_audits.where(
          auditable_type: 'PhoneNumber',
        ).reorder(created_at: :desc)

        mobile_phone = member.phone_numbers.mobile.first

        id_change_date = described_class.get_id_change_date(
          member,
          :mobile,
          mobile_phone.updated_at || member.updated_at
        )

        expect(id_change_date).to eq(mobile_phone.updated_at)
          .or(eq(last_audit_log_with_change.created_at))
          .or(eq(member.updated_at))
        expect(last_audit_log_with_change.audited_changes.key?('phone'))
          .to be(true)
        expect(audit_logs.count).to eq(2)
      end

      it 'correctly identifies the change date for landline' do
        member = nil

        travel_to(3.minutes.ago) do
          member = FactoryBot.create(:member)
          member.update_phone_number('293335555')
        end

        travel_to(2.minutes.ago) do
          member.update_phone_number('293335555')
        end

        last_audit_log_with_change = nil
        travel_to(1.minute.ago) do
          member.update_phone_number('61291115555')
          last_audit_log_with_change = member.associated_audits.where(
            auditable_type: 'PhoneNumber',
          ).reorder(created_at: :desc).first
        end

        member.update_phone_number('61291115555')
        member.phone_numbers.reload

        # NB: we'll only have `2` audits as `update_phone_number`
        # will simply return if the new phone number is same
        # as the existing one.
        audit_logs = member.associated_audits.where(
          auditable_type: 'PhoneNumber',
        ).reorder(created_at: :desc)

        landline = member.phone_numbers.landline.first

        id_change_date = described_class.get_id_change_date(
          member,
          :landline,
          landline.updated_at || member.updated_at
        )

        expect(id_change_date).to eq(landline.updated_at)
          .or(eq(last_audit_log_with_change.created_at))
          .or(eq(member.updated_at))
        expect(last_audit_log_with_change.audited_changes.key?('phone'))
          .to be(true)
        expect(audit_logs.count).to eq(2)
      end

      it 'correctly identifies the change date for address' do
        member = nil

        travel_to(3.minutes.ago) do
          member = FactoryBot.create(:member)
          member.update_address({ town: 'Newtown', postcode: '2042' })
        end

        travel_to(2.minutes.ago) do
          member.update_address({ town: 'Newtown', postcode: '2042' })
        end

        last_audit_log_with_change = nil
        travel_to(1.minute.ago) do
          member.update_address({ town: 'Coburg', postcode: '3021' })
          last_audit_log_with_change = member.associated_audits.where(
            auditable_type: 'Address',
          ).reorder(created_at: :desc).first
        end

        member.address.touch! # fake address update
        member.addresses.reload

        audit_logs = member.associated_audits.where(
          auditable_type: 'Address',
        ).reorder(created_at: :desc)

        id_change_date = described_class.get_id_change_date(
          member,
          :address,
          member.address.updated_at || member.updated_at
        )

        # These test modifications are part of the temporary workaround
        # in `get_id_change_date` for obtaining change timestamp from the
        # `member.address.updated_at` and not from the audit log.
        expect(id_change_date).to eq(member.address.updated_at)
        expect(id_change_date).not_to eq(last_audit_log_with_change.created_at)

        # These are the original assertions and should be reinstated once the
        # temporary workaround is resolved.
        # expect(id_change_date).to eq(last_audit_log_with_change.created_at)
        #   .or(eq(member.address.updated_at))
        #   .or(eq(member.updated_at))
        expect(last_audit_log_with_change.audited_changes.key?('line1'))
          .to be(true)
        expect(audit_logs.count).to eq(3)
      end

      it 'correctly identifies the change date for email subscription' do
        member = nil

        travel_to(3.minutes.ago) do
          member = FactoryBot.create(:member)
          member.subscribe_to(Subscription::EMAIL_SUBSCRIPTION)
        end

        travel_to(2.minutes.ago) do
          member.unsubscribe_from(Subscription::EMAIL_SUBSCRIPTION)
        end

        last_audit_log_with_change = nil
        travel_to(1.minute.ago) do
          member.subscribe_to(Subscription::EMAIL_SUBSCRIPTION)
          last_audit_log_with_change = member.associated_audits.where(
            auditable_type: 'MemberSubscription',
          ).reorder(created_at: :desc).first
        end

        member.subscribe_to(Subscription::EMAIL_SUBSCRIPTION)

        audit_logs = member.associated_audits.where(
          auditable_type: 'MemberSubscription',
        ).reorder(created_at: :desc)

        email_sub = member.member_subscriptions.find_by(
          subscription_id: Settings.tijuana.email_subscription_id
        )

        id_change_date = described_class.get_id_change_date(
          member,
          :email_subscription,
          email_sub.updated_at || member.updated_at
        )

        expect(id_change_date).to eq(last_audit_log_with_change.created_at)
          .or(eq(email_sub.updated_at))
          .or(eq(member.updated_at))
        expect(last_audit_log_with_change.audited_changes.key?('subscribed_at'))
          .to be(true)
        expect(audit_logs.count).to eq(4)
      end

      it 'correctly identifies the change date for sms subscription' do
        member = nil

        travel_to(3.minutes.ago) do
          member = FactoryBot.create(:member)
          member.subscribe_to(Subscription::SMS_SUBSCRIPTION)
        end

        travel_to(2.minutes.ago) do
          member.unsubscribe_from(Subscription::SMS_SUBSCRIPTION)
        end

        last_audit_log_with_change = nil
        travel_to(1.minute.ago) do
          member.subscribe_to(Subscription::SMS_SUBSCRIPTION)
          last_audit_log_with_change = member.associated_audits.where(
            auditable_type: 'MemberSubscription',
          ).reorder(created_at: :desc).first
        end

        member.subscribe_to(Subscription::SMS_SUBSCRIPTION)

        audit_logs = member.associated_audits.where(
          auditable_type: 'MemberSubscription',
        ).reorder(created_at: :desc)

        sms_sub = member.member_subscriptions.find_by(
          subscription_id: Settings.tijuana.sms_subscription_id
        )

        id_change_date = described_class.get_id_change_date(
          member,
          :sms_subscription,
          sms_sub.updated_at || member.updated_at
        )

        expect(id_change_date).to eq(last_audit_log_with_change.created_at)
          .or(eq(sms_sub.updated_at))
          .or(eq(member.updated_at))
        expect(last_audit_log_with_change.audited_changes.key?('subscribed_at'))
          .to be(true)
        expect(audit_logs.count).to eq(4)
      end

      it 'correctly identifies the change date for calling subscription' do
        member = nil

        travel_to(3.minutes.ago) do
          member = FactoryBot.create(:member)
          member.subscribe_to(Subscription::CALLING_SUBSCRIPTION)
        end

        travel_to(2.minutes.ago) do
          member.unsubscribe_from(Subscription::CALLING_SUBSCRIPTION)
        end

        last_audit_log_with_change = nil
        travel_to(1.minute.ago) do
          member.subscribe_to(Subscription::CALLING_SUBSCRIPTION)
          last_audit_log_with_change = member.associated_audits.where(
            auditable_type: 'MemberSubscription',
          ).reorder(created_at: :desc).first
        end

        member.subscribe_to(Subscription::CALLING_SUBSCRIPTION)

        audit_logs = member.associated_audits.where(
          auditable_type: 'MemberSubscription',
        ).reorder(created_at: :desc)

        call_sub = member.member_subscriptions.find_by(
          subscription_id: Settings.tijuana.calling_subscription_id
        )

        id_change_date = described_class.get_id_change_date(
          member,
          :calling_subscription,
          call_sub.updated_at || member.updated_at
        )

        expect(id_change_date).to eq(last_audit_log_with_change.created_at)
          .or(eq(call_sub.updated_at))
          .or(eq(member.updated_at))
        expect(last_audit_log_with_change.audited_changes.key?('subscribed_at'))
          .to be(true)
        expect(audit_logs.count).to eq(4)
      end
    end
  end
end
