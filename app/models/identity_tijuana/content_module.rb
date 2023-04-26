module IdentityTijuana
  class ContentModule < ReadWrite
    self.table_name = 'content_modules'
    has_many :content_module_links
    has_many :pages, :through => :content_module_links

    def self.inheritance_column
      "dummy"
    end

    # The many-to-many relationship between content modules and pages
    # that exists in TJ cannot be replicated exactly in ID, because an action
    # in ID is linked to exactly one campaign. So we must represent this
    # via duplicate ID actions where required.
    def self.content_modules_sql
      %{
        select distinct
          ps.id as page_sequence_id,
          cm.id as content_module_id,
          cm.updated_at as content_module_updated_at
        from content_modules cm
        join content_module_links cml
          on cml.content_module_id = cm.id
        join pages p
          on p.id = cml.page_id
         and p.deleted_at is null
        join page_sequences ps
          on ps.id = p.page_sequence_id
         and ps.deleted_at is null
      }
    end

    def self.content_modules_all
      connection.execute(content_modules_sql).to_a
    end

    def self.updated_content_modules_sql(last_updated_at, last_id, exclude_from)
      %{
        #{content_modules_sql}
        where (cm.updated_at > '#{last_updated_at}'
          or (cm.updated_at = '#{last_updated_at}' and cm.id > #{last_id}))
        and cm.updated_at < '#{exclude_from}'
      }
    end

    def self.updated_content_modules(last_updated_at, last_id, exclude_from)
      limit = Settings.tijuana.pull_batch_amount
      limit_clause = limit.present? ? "limit #{limit}" : ""
      connection.execute(
        %{
          #{updated_content_modules_sql(last_updated_at, last_id, exclude_from)}
          order by cm.updated_at, cm.id
          #{limit_clause}
        }
      ).to_a
    end

    def self.updated_content_modules_all(last_updated_at, last_id, exclude_from)
      connection.execute(
        updated_content_modules_sql(last_updated_at, last_id, exclude_from)
      ).to_a
    end

    def description
      self.title.present? ? "#{self.type}: #{self.title}" : "#{self.type}"
    end

    def import(sync_id, page_sequence_id)
      begin
        # The content_modules table in TJ maps onto the actions table in ID.
        action = ::Action.find_or_create_by(external_id: "#{page_sequence_id}_#{self.id}", external_source: 'tijuana')
        action.name = self.description
        # action.action_type = nil
        # action.technical_type = nil
        # action.old_action_id = nil
        action.campaign = ::Campaign.find_by(external_id: page_sequence_id.to_s, external_source: 'tijuana_page_sequence')
        # action.description = nil
        # action.status = nil
        # action.public_name = nil
        # action.language = nil
        action.save!
      rescue Exception => e
        Rails.logger.error "Tijuana content modules sync id:#{self.id}, error: #{e.message}"
        raise
      end
    end
  end
end
