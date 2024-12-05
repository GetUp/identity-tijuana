module IdentityTijuana
  class UserEmail < ReadWrite
    self.table_name = 'user_emails'

    belongs_to :user
  end
end
