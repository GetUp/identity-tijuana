module IdentityTijuana
  class ContentModuleLink < ReadWrite
    self.table_name = 'content_module_links'
    belongs_to :page
    belongs_to :content_module
  end
end
