require 'identity_tijuana/application_record'
require 'identity_tijuana/readwrite'

module ExternalSystems::IdentityTijuana
  class Donation < ApplicationRecord
    include ReadWrite
    self.table_name = 'donations'

    def self.import(donation_id)
      donation = Donation.find(donation_id)
      donation.import(donation_id)
    end

    def import(donation_id)
      user = User.find(user_id)
      member = Member.find_by_email(user.email)

      regular_donation_hash = {
        external_id: donation_id,
        member_id: member.id,
        frequency: frequency, 
        started_at: created_at,
        ended_at: cancelled_at,
        source: content_module_id,
        initial_amount: amount.to_f / 100,
        current_amount: amount.to_f / 100,
        donations: []
      }
    end
  end
end
