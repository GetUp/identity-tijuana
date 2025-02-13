require 'rails_helper'

describe IdentityTijuana::UserGhosting do
  before(:each) do
    allow(Settings).to(
      receive_message_chain("tijuana.database_url") { ENV['TIJUANA_DATABASE_URL'] }
    )
    allow(Settings).to(
      receive_message_chain("ghoster.email_domain") { 'anoned.non' }
    )
  end

  context '#ghosting' do
    let(:anon_domain) { Settings.ghoster.email_domain }
    let(:enhanced_error) {
      ->(attr, expected, actual) {
        "Expected #{attr} to be #{expected}, but got #{actual}"
      }
    }

    it 'should ghost user profile' do
      user = FactoryBot.create(:tijuana_user_with_everything)
      original_attributes = user.attributes.symbolize_keys

      described_class.new([user.id], 'test-reason').ghost_users

      user.reload

      expect(user.email).to eq("#{user.id}@#{anon_domain}")

      nils = [:first_name, :last_name, :mobile_number,
              :home_number, :street_address, :country_iso,
              :encrypted_password, :password_salt, :reset_password_token,
              :postcode_id, :quick_donate_trigger_id, :facebook_id,
              :otp_secret_key, :current_sign_in_ip, :last_sign_in_ip]

      nils.each do |prop|
        expect(user.send(prop)).to be(nil)
      end

      falsey = [:is_member, :is_admin, :active]

      falsey.each do |prop|
        expect(user.send(prop)).to eq(false)
      end

      truthy = [:do_not_call, :do_not_sms]

      truthy.each do |prop|
        expect(user.send(prop)).to eq(true)
      end

      # Ignoring :random because of potential precision changes
      unchanged_attributes = original_attributes.except(*nils,
                                                        *truthy,
                                                        *falsey,
                                                        :random,
                                                        :email,
                                                        :updated_at)

      unchanged_attributes.each do |attr, value|
        expect(user.send(attr)).to eq(value), enhanced_error.call(attr, value, user.send(attr))
      end
    end

    it 'should ghost call_outcomes' do
      u = FactoryBot.create(:tijuana_user)
      co = FactoryBot.create(:call_outcome,
                             email: u.email,
                             user: u,
                             payload: 'some PI data',
                             dialed_number: '0411 123 123',
                             disposition: 'No Answer',
                             donation_email: 'different@donation-email.com',)
      original_attributes = co.attributes.symbolize_keys

      described_class.new([u.id], 'test-reason').ghost_users
      co.reload

      nils = [:email, :payload, :dialed_number, :donation_email]

      nils.each do |prop|
        expect(co.send(prop)).to eq(nil)
      end

      unchanged_attributes = original_attributes.except(*nils,
                                                        :updated_at)

      unchanged_attributes.each do |attr, value|
        expect(co.send(attr)).to eq(value), enhanced_error.call(attr, value, co.send(attr))
      end
    end

    it 'should ghost comments' do
      skip 'comments may be abandoned - not to be ghosted'
    end

    it 'should ghost donations' do
      u = FactoryBot.create(:tijuana_user)
      d = IdentityTijuana::Donation.create!(
        user: u,
        page_id: 1,
        email_id: 1,
        content_module_id: 1,
        active: true,
        amount_in_cents: 1000,
        payment_method: 'credit-card',
        frequency: 'one-off',
        name_on_card: u.first_name,
        card_type: 'visa',
        card_expiry_month: 01,
        card_expiry_year: 2025,
        card_last_four_digits: '7777',
        cheque_name: u.first_name,
        cheque_number: '123456789',
        cheque_bank: 'Your Choice',
        cheque_branch: 'Green',
        cheque_bsb: '088-999',
        cheque_account_number: '987654321',
        cancel_reason: 'Just testing',

        paypal_subscr_id: 100,
        identifier: 'Joe Money Inc',
        dynamic_attributes: 'Some PI or SI info',
      )

      original_attributes = d.attributes.symbolize_keys

      described_class.new([u.id], 'test-reason').ghost_users

      d.reload

      nils = [:name_on_card, :cheque_name, :identifier, :dynamic_attributes]

      nils.each do |prop|
        expect(d.send(prop)).to eq(nil), enhanced_error.call(prop, nil, d.send(prop))
      end

      unchanged_attributes = original_attributes.except(*nils, :updated_at)

      unchanged_attributes.each do |attr, value|
        expect(d.send(attr)).to eq(value), enhanced_error.call(attr, value, d.send(attr))
      end
    end

    it 'should ghost facebook_users' do
      u = FactoryBot.create(:tijuana_user)
      fbu = IdentityTijuana::FacebookUser.create!(
        user_id: u.id,
        facebook_id: 100,
        app_id: 1,
      )

      original_attributes = fbu.attributes.symbolize_keys

      described_class.new([u.id], 'test-reason').ghost_users

      fbu.reload

      nils = [:facebook_id]

      nils.each do |prop|
        expect(fbu.send(prop)).to eq(nil)
      end

      unchanged_attributes = original_attributes.except(*nils, :updated_at)

      unchanged_attributes.each do |attr, value|
        expect(fbu.send(attr)).to eq(value), enhanced_error.call(attr, value, fbu.send(attr))
      end
    end

    it 'should ghost merge_records' do
      u = FactoryBot.create(:tijuana_user)
      mr = IdentityTijuana::MergeRecord.create!(
        join_id: u.email,
        merge_id: 1,
        name: 'id',
        value: '12345',
      )

      original_attributes = mr.attributes.symbolize_keys

      described_class.new([u.id], 'test-reason').ghost_users

      mr.reload

      nils = [:join_id, :value]

      nils.each do |prop|
        expect(mr.send(prop)).to eq(nil)
      end

      unchanged_attributes = original_attributes.except(*nils, :updated_at)

      unchanged_attributes.each do |attr, value|
        expect(mr.send(attr)).to eq(value), enhanced_error.call(attr, value, mr.send(attr))
      end
    end

    it 'should ghost image_shares' do
      u = FactoryBot.create(:tijuana_user)
      is = IdentityTijuana::ImageShare.create!(
        user: u,
        content_module_id: 1,
        page_id: 1,
        email_id: 1,
        image_url: 'https://getup.org/image.jpg',
        caption: 'Some PI or SI data is here',
      )

      original_attributes = is.attributes.symbolize_keys

      described_class.new([u.id], 'test-reason').ghost_users

      is.reload

      empties = [:caption]

      empties.each do |prop|
        expect(is.send(prop)).to eq('')
      end

      unchanged_attributes = original_attributes.except(*empties, :updated_at)

      unchanged_attributes.each do |attr, value|
        expect(is.send(attr)).to eq(value), enhanced_error.call(attr, value, is.send(attr))
      end
    end

    it 'should ghost petition_signatures' do
      u = FactoryBot.create(:tijuana_user)
      ps = IdentityTijuana::PetitionSignature.create!(
        user: u,
        content_module_id: 1,
        page_id: 1,
        email_id: 1,
        dynamic_attributes: 'Some PI or SI data is here',
      )

      original_attributes = ps.attributes.symbolize_keys

      described_class.new([u.id], 'test-reason').ghost_users

      ps.reload

      nils = [:dynamic_attributes]

      nils.each do |prop|
        expect(ps.send(prop)).to eq(nil)
      end

      unchanged_attributes = original_attributes.except(*nils, :updated_at)

      unchanged_attributes.each do |attr, value|
        expect(ps.send(attr)).to eq(value), enhanced_error.call(attr, value, ps.send(attr))
      end
    end

    it 'should ghost testimonials' do
      u = FactoryBot.create(:tijuana_user)
      t = IdentityTijuana::Testimonial.create!(
        user: u,
        content_module_id: 1,
        page_id: 1,
        email_id: 1,
        facebook_user_id: 123456789,
      )

      original_attributes = t.attributes.symbolize_keys

      described_class.new([u.id], 'test-reason').ghost_users

      t.reload

      nils = [:facebook_user_id]

      nils.each do |prop|
        expect(t.send(prop)).to eq(nil)
      end

      unchanged_attributes = original_attributes.except(*nils, :updated_at)

      unchanged_attributes.each do |attr, value|
        expect(t.send(attr)).to eq(value), enhanced_error.call(attr, value, t.send(attr))
      end
    end

    it 'should ghost user_activity_events' do
      u = FactoryBot.create(:tijuana_user)
      uae = IdentityTijuana::UserActivityEvent.create!(
        user: u,
        activity: 'activity',
        campaign_id: 1,
        page_sequence_id: 1,
        page_id: 1,
        content_module_id: 1,
        content_module_type: 'module-type',
        user_response_id: 1,
        user_response_type: 'user_response_type',
        public_stream_html: 'Sensitive PI data',
        donation_amount_in_cents: 1000,
        donation_frequency: 'donation_frequency',
        email_id: 1,
        push_id: 1,
        source: 'source',
        acquisition_source_id: 1,
      )

      original_attributes = uae.attributes.symbolize_keys

      described_class.new([u.id], 'test-reason').ghost_users

      uae.reload

      nils = [:public_stream_html]

      nils.each do |prop|
        expect(uae.send(prop)).to eq(nil)
      end

      unchanged_attributes = original_attributes.except(*nils, :updated_at)

      unchanged_attributes.each do |attr, value|
        expect(uae.send(attr)).to eq(value), enhanced_error.call(attr, value, uae.send(attr))
      end
    end

    it 'should ghost user_emails' do
      u = FactoryBot.create(:tijuana_user)
      ue = IdentityTijuana::UserEmail.create!(
        user: u,
        content_module_id: 1,
        subject: 'subject line',
        body: 'email content with some PI data',
        from: 'Some PI data',
        targets: 'targets emails',
        email_id: 1,
        page_id: 1,
        cc_me: true,
        send_to_target: 'send_to_target',
        dynamic_attributes: 'Non PI data',
      )

      original_attributes = ue.attributes.symbolize_keys

      described_class.new([u.id], 'test-reason').ghost_users

      ue.reload

      empties = [:body, :from]

      empties.each do |prop|
        expect(ue.send(prop)).to eq('')
      end

      unchanged_attributes = original_attributes.except(*empties, :updated_at)

      unchanged_attributes.each do |attr, value|
        expect(ue.send(attr)).to eq(value), enhanced_error.call(attr, value, ue.send(attr))
      end
    end

    it 'should not ghost users with active recurring donations' do
      user = FactoryBot.create(:tijuana_user_with_everything)
      u2 = FactoryBot.create(:tijuana_user_with_everything)
      FactoryBot.create(
        :tijuana_donation,
        user: user,
        content_module_id: 1,
        page_id: 1,
        cover_processing_fee: 1,
        amount_in_cents: 1000,
        payment_method: 'credit-card',
        frequency: 'monthly',
        make_recurring_at: Time.current,
        active: true,
        cancelled_at: nil
      )

      expect(user.email).not_to include(anon_domain)

      expect(Rails.logger).to receive(:error).with(
        /Members \[ids: #{user.id}\] with active recurring donations cannot be anonymised!/
      )

      expect {
        described_class.new([user.id, u2.id], 'test-reason').ghost_users
      }.not_to change { user.reload.email }
    end

    it 'should fail if no member ids are provided for ghosting' do
      expect(Rails.logger).to receive(:error).with(
        /No member ids provided to anonymise/
      )

      described_class.new([], 'test-reason').ghost_users
    end
  end
end
