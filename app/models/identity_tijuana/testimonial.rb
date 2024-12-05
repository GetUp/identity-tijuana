module IdentityTijuana
  class Testimonial < ReadWrite
    self.table_name = 'testimonials'

    belongs_to :user
  end
end
