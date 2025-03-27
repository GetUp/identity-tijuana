module IdentityTijuana
  class PetitionSignature < ReadWrite
    self.table_name = 'petition_signatures'

    belongs_to :user
  end
end
