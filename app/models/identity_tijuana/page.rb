module IdentityTijuana
  class Page < ReadWrite
    self.table_name = 'pages'
    belongs_to :page_sequence
    has_many :content_module_links
    has_many :content_modules, through: :content_module_links
  end
end
