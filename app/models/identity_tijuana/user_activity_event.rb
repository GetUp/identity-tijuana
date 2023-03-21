module IdentityTijuana
  class UserActivityEvent < ReadWrite
    self.table_name = 'user_activity_events'
    belongs_to :user
  end
end
