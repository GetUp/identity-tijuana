module IdentityTijuana
  class CallOutcome < ReadWrite
    self.table_name = 'call_outcomes'

    belongs_to :user
  end
end
