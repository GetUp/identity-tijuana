module IdentityTijuana
  class DonationUpgrade < ApplicationRecord
    include ReadWrite
    self.table_name = 'donation_upgrades'
    belongs_to :donation
  end
end
