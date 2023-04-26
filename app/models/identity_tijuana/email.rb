module IdentityTijuana
  class Email < ReadWrite
    self.table_name = 'emails'
    belongs_to :blast
  end
end
