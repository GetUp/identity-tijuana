class Donations::FailedDonation < ApplicationRecord
  belongs_to :member, optional: true
  belongs_to :regular_donation, optional: true
end
