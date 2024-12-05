module IdentityTijuana
  class AnonymisationLog < ReadWrite
    self.table_name = 'anonymisation_logs'
    belongs_to :user
  end
end
