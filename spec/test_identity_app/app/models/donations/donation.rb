# == Schema Information
#
# Table name: donations
#
# id               :integer    not null, primary key
# member_action_id :integer
# member_id        :integer
# amount           :float
# external_source  :text
# created_at       :datetime
# updated_at       :datetime
# external_id      :text
#
class Donations::Donation < ApplicationRecord
  belongs_to :member_action, optional: true
  belongs_to :member
  belongs_to :regular_donation, class_name: 'Donations::RegularDonation', optional: true

  validates_uniqueness_of :amount, scope: %i[member_id created_at]

  def self.card_mapping
    {
      'Visa' => 'vs',
      'American Express' => 'ax',
      'MasterCard' => 'mc',
      'Discover' => 'ds',
      'JCB' => 'ck',
      'Diners Club' => 'ck',
      'Unknown' => 'ck'
    }
  end

  def self.nonce_used?(nonce)
    Donation.where(nonce: nonce.to_s).count > 0
  end

  def self.log_quick_donate(member_id, amount, stripe_charge_id, nonce)
    Donation.create!(member_id: member_id,
                     amount: amount.to_f / 100,
                     external_source: 'stripe:quick_donate',
                     external_id: stripe_charge_id,
                     nonce: nonce,
                     medium: 'quick_donate')
  end

  def self.create_from_stripe_webhook!(event_data)
    object = event_data['data']['object']
    unless event_data['type'] == 'charge.succeeded' && object['metadata']['takecharge-tag-0']
      return
    end

    member_hash = {
      emails: [{ email: object['metadata']['email'] }],
      external_ids: { controlshift: object['metadata']['takecharge-tag-3'].gsub('agra-member:', '').to_i }
    }
    member = UpsertMember.call(member_hash, ignore_name_change: Settings.options.ignore_name_change_for_donation)

    Donations::Donation.create!(
      member: member,
      amount: object['amount'].to_i / 100,
      external_source: object['metadata']['takecharge-tag-2'],
      created_at: DateTime.strptime(object['created'].to_s, "%s"),
      external_id: object['id'],
      medium: 'stripe'
    )
  end

  def self.upsert!(attrs)
    # rubocop:disable Rails/SaveBang
    if attrs[:external_id].present?
      donation = Donations::Donation.find_or_create_by(attrs.slice(:medium, :external_id)) do |don|
        don.assign_attributes(attrs.except(:medium, :external_id))
      end
    end

    # Sometimes a save fails because the donation already exists but was missing an external_id (was not found)
    # Use a find based on other attrs instead to try and find and merge the donation
    if donation.blank? || donation.invalid?
      donation = Donations::Donation.find_or_create_by(attrs.slice(:medium, :member_id, :amount, :created_at)) do |don|
        don.assign_attributes(attrs.except(:medium, :member_id, :amount, :created_at))
      end
    end
    donation.save!
    # rubocop:enable Rails/SaveBang
    return donation
  end
end
