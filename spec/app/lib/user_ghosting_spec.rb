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
    context 'user with all attributes' do
      it 'should ghost all attributes' do
        u = FactoryBot.create(:tijuana_user_with_everything)

        anon_domain = Settings.ghoster.email_domain
        described_class.new([u.id], 'test-reason').ghost_users

        u.reload

        expect(u.email).to eq("#{u.id}@#{anon_domain}")

        nils = [:first_name, :last_name, :mobile_number,
                :home_number, :street_address, :country_iso,
                :encrypted_password, :password_salt, :reset_password_token,
                :remember_created_at, :current_sign_in_at, :last_sign_in_at,
                :current_sign_in_ip, :last_sign_in_ip, :postcode_id,
                :random, :notes, :quick_donate_trigger_id, :facebook_id,
                :otp_secret_key, :tracking_token]

        nils.each do |prop|
          expect(u.send(prop)).to be(nil)
        end

        falsey = [:is_member, :is_admin, :active, :is_volunteer]

        falsey.each do |prop|
          expect(u.send(prop)).to eq(false)
        end

        truthy = [:do_not_call, :do_not_sms]

        truthy.each do |prop|
          expect(u.send(prop)).to eq(true)
        end
      end
    end
  end
end
