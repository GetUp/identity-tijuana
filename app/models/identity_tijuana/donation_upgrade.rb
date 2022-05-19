module IdentityTijuana
  class DonationUpgrade < ReadWrite
    self.table_name = 'donation_upgrades'
    belongs_to :donation
  end
end
