module IdentityTijuana
  class MemberSync
    # Sync an ID member with TJ.
    def self.export_member(member_id)
      member = Member.find(member_id)
      return if member.ghosting_started?
      ext_id = MemberExternalId.find_by(system: 'tijuana', member: member)
      user_id = ext_id.external_id if ext_id.present?
      if user_id.present?
        user = User.find_by(id: user_id)
        ext_id.destroy if user.blank?
      end
      if user.blank?
        sync_type = :merge
        email = member.email
        user = User.find_by(email: email) if email.present?
        sync_type = :create if user.blank?
      else
        sync_type = :update
      end

      sync(user, member, sync_type)
    end

    # Sync a TJ user with ID.
    def self.import_user(user_id)
      user = User.find(user_id)
      member = Member.find_by_external_id(:tijuana, user_id)

      if member.blank?
        sync_type = :merge
        cleansed_email = Cleanser.cleanse_email(user.email)
        cleansed_email = nil unless Cleanser.accept_email?(cleansed_email)
        member = Member.find_by(email: cleansed_email) if cleansed_email.present?
      else
        sync_type = :update
      end

      if member.blank?
        sync_type = :create
      else
        if member.ghosting_started?
          Rails.logger.warn "Tijuana member (#{user.id}) is ghosted (#{member.id}), not updating"
          return
        end
      end

      sync(user, member, sync_type)
    end

    private

    # Parameters for searching the active_record_audits table.
    AUDIT_SEARCH_PARAMS = {
      name: ['audits', 'Member', %w[first_name last_name]],
      email: ['audits', 'Member', %w[email]],
      mobile: ['associated_audits', 'PhoneNumber', %w[phone]],
      landline: ['associated_audits', 'PhoneNumber', %w[phone]],
      address: ['associated_audits', 'Address', %w[line1 line2 town country state postcode]],
      email_subscription: ['associated_audits', 'MemberSubscription', %w[unsubscribed_at]],
      sms_subscription: ['associated_audits', 'MemberSubscription', %w[unsubscribed_at]],
      calling_subscription: ['associated_audits', 'Member_subscription', %w[unsubscribed_at]],
      rts: ['associated_audits', 'CustomField', %w[data]],
      deceased: ['associated_audits', 'CustomField', %w[data]],
    }

    # Use the audit log to work out the date/time a given field or set of
    # fields was last changed in ID.
    def self.get_id_change_date(member, field_info_type, default_change_date = nil)
      # Default change date to the epoch if not passed, or if passed as nil.
      default_change_date = Time.at(0) if default_change_date.nil?
      # Must have a member to search against!
      return default_change_date if member.nil?
      # Pull parameters to drive the audit log search.
      audit_list_name, auditable_type, audit_field_names = AUDIT_SEARCH_PARAMS[field_info_type]
      # Check whether we have an ancillary matching field.
      ancillary_match_value = nil
      case auditable_type
      when 'CustomField'
        # For custom fields, need to make sure that changes relate to the
        # correct custom field.
        ancillary_match_value = CustomFieldKey.find_by(name: field_info_type)&.id
      when 'PhoneNumber'
        # For phone numbers, need to make sure that changes relate to the
        # correct type of phone number.
        ancillary_match_value = field_info_type
      when 'MemberSubscription'
        # For subscriptions, need to make sure that changes relate to the
        # correct type of subscription.
        case field_info_type
        when :email_subscription
          ancillary_match_value = Settings.tijuana.email_subscription_id
        when :sms_subscription
          ancillary_match_value = Settings.tijuana.sms_subscription_id
        when :calling_subscription
          ancillary_match_value = Settings.tijuana.calling_subscription_id
        end
      end
      # Iterate through the relevant audit log list, moving backwards in time
      # until we find a change to the field or fields in question.
      member.send(audit_list_name).where(auditable_type: auditable_type).reverse_each do |audit|
        # Check ancillary matching field, where required.
        if !ancillary_match_value.nil?
          case auditable_type
          when 'CustomField'
            audit_custom_field_key_id =
              audit.audited_changes['custom_field_key_id'] ||
                CustomField.find_by(id: audit.auditable_id).try(:custom_field_key_id)
            next unless audit_custom_field_key_id == ancillary_match_value
          when 'PhoneNumber'
            phone_number_type =
              audit.audited_changes['phone_type'] ||
                PhoneNumber.find_by(id: audit.auditable_id).try(:phone_type)
            next unless phone_number_type == ancillary_match_value
          when 'MemberSubscription'
            audit_subscription_id =
              audit.audited_changes['subscription_id'] ||
                MemberSubscription.find_by(id: audit.auditable_id).try(:subscription_id)
            next unless audit_subscription_id == ancillary_match_value
          end
        end
        # Search for changes to *any* of the fields in the associated list. For
        # example, a change to either the first name or the last name is
        # considered a "name change".
        audit_field_names.each do |audit_field_name|
          # The audited_changes field is a JSON blob that can be interrogated
          # for the presence or absence of the field we're interested in.
          if audit.audited_changes.key?(audit_field_name)
            return audit.created_at
          end
        end
      end
      # Return the default if no matching field change was found in the audit list.
      default_change_date
    end

    # This function compares two sets of logically related field values. It
    # determines which of the two sets is more desirable, and then takes action
    # via a callback based on that decision.
    def self.compare_fields(
      sync_type,
      id_field_values, tj_field_values,
      id_datestamp_func, tj_datestamp_func,
      id_action_func, tj_action_func
    )
      id_vals = id_field_values.map {|e| e == '' ? nil : e}
      tj_vals = tj_field_values.map {|e| e == '' ? nil : e}
      return if id_vals == tj_vals
      id_val_count = id_vals.reject(&:nil?).count
      tj_val_count = tj_vals.reject(&:nil?).count
      case sync_type
      when :create
        # Create scenario is when the member doesn't exist yet in one system.
        # This case is simple as the system with the information wins.
        if tj_val_count > 0
          id_action_func.call
        elsif id_val_count > 0
          tj_action_func.call
        end
      when :update
        # Update scenario is when the member exists in ID and has previously
        # been matched to a corresponding record in TJ. In this case, the most
        # recent change wins.
        if id_datestamp_func.call >= tj_datestamp_func.call
          tj_action_func.call
        else
          id_action_func.call
        end
      when :merge
        # Merge scenario is when the member exists in one system, but has not
        # previously been matched to a corresponding record in the other. In
        # this case, we try to create as complete a version of the member as
        # possible, by merging the two sets of information. Thus, a populated
        # field value wins over an unpopulated field value. If values are
        # present in both systems, then the most complete set of information
        # wins, unless there is a conflict. In that case the most recent
        # change wins.
        if id_val_count > 0 && tj_val_count == 0
          tj_action_func.call
        elsif id_val_count == 0 && tj_val_count > 0
          id_action_func.call
        elsif id_val_count > 0 && tj_val_count > 0
          conflicts = id_vals.zip(tj_vals).map{ |i, t| !i.nil? && !t.nil? && i != t ? 1 : 0 }.sum
          if conflicts > 0
            if id_datestamp_func.call > tj_datestamp_func.call
              tj_action_func.call
            else
              id_action_func.call
            end
          elsif id_val_count > tj_val_count
            tj_action_func.call
          else
            id_action_func.call
          end
        end
      end
    end

    # This function performs a sync between a user and a member.
    def self.sync(user, member, sync_type)
      member_hash = { }
      tj_changes = { }
      user_updated_at = user&.updated_at || Time.at(0)

      # Compare first & last names.
      compare_fields(
        sync_type,
        [ member&.first_name, member&.last_name ],
        [ user&.first_name, user&.last_name ],
        Proc.new { get_id_change_date(member, :name, member&.updated_at) },
        Proc.new { user_updated_at },
        Proc.new {
          member_hash[:firstname] = user.first_name
          member_hash[:lastname] = user.last_name
        },
        Proc.new {
          tj_changes[:first_name] = member.first_name
          tj_changes[:last_name] = member.last_name
        }
      )

      # Compare email address.
      abort_sync = false
      compare_fields(
        sync_type, [ member&.email ], [ user&.email ],
        Proc.new { get_id_change_date(member, :email, member&.updated_at) },
        Proc.new { user_updated_at },
        Proc.new { member_hash[:emails] = [{email: user.email}] },
        Proc.new {
          existing_user_with_same_email = User.find_by(email: member.email)
          if existing_user_with_same_email.present?
            # We can't update the email in TJ if another user already exists
            # with that email address. In that scenario, the current user
            # needs to be unlinked from the member, and we need to ensure
            # that the other user is linked instead.
            MemberExternalId.where(
              member: member,
              system: 'tijuana',
              external_id: user.id.to_s
            ).destroy_all
            abort_sync = true
          else
            tj_changes[:email] = member.email
          end
        }
      )
      return if abort_sync

      # Compare mobile number.
      id_mobile = member&.phone_numbers&.mobile&.first
      id_mobile_number = id_mobile&.phone
      tj_mobile_number = standardise_phone_number(user&.mobile_number)
      compare_fields(
        sync_type, [ id_mobile_number ], [ tj_mobile_number ],
        Proc.new { get_id_change_date(member, :mobile, id_mobile&.updated_at || member&.updated_at) },
        Proc.new { user_updated_at },
        Proc.new {
          member_hash[:phones] = [] unless member_hash.has_key?(:phones)
          member_hash[:phones].push(phone: tj_mobile_number)
        },
        Proc.new { tj_changes[:mobile_number] = id_mobile_number }
      )

      # Compare home/landline number.
      id_landline = member&.phone_numbers&.landline&.first
      id_landline_number = id_landline&.phone
      tj_landline_number = standardise_phone_number(user&.home_number)
      compare_fields(
        sync_type, [ id_landline_number ], [ tj_landline_number ],
        Proc.new { get_id_change_date(member, :landline, id_landline&.updated_at || member&.updated_at) },
        Proc.new { user_updated_at },
        Proc.new {
          member_hash[:phones] = [] unless member_hash.has_key?(:phones)
          member_hash[:phones].push(phone: tj_landline_number)
        },
        Proc.new { tj_changes[:home_number] = id_landline_number }
      )

      # Compare address.
      member_address = member&.address
      user_postcode = user&.postcode
      compare_fields(
        sync_type,
        [ member_address&.line1, member_address&.line2, member_address&.town,
          member_address&.country, member_address&.state, member_address&.postcode ],
        [ user&.street_address, nil, user&.suburb,
          user&.country_iso, user_postcode&.state, user_postcode&.number ],
        Proc.new { get_id_change_date(member, :address, member_address&.updated_at || member&.updated_at) },
        Proc.new { user_updated_at },
        Proc.new {
          address_hash = {
            line1: user.street_address,
            line2: nil,
            town: user.suburb,
            country: user.country_iso,
            state: user_postcode&.state,
            postcode: user_postcode&.number
          }
          member_hash[:addresses] = [address_hash]
        },
        Proc.new {
          tj_changes[:street_address] = member_address&.line1
          tj_changes[:suburb] = member_address&.town
          tj_changes[:country] = member_address&.country
          tj_changes[:state] = member_address&.state
          tj_changes[:postcode] = member_address&.postcode
        }
      )

      # Compare subscription to email.
      id_email_sub = member&.member_subscriptions&.find_by(subscription_id: Settings.tijuana.email_subscription_id)
      id_email_subbed = id_email_sub ? id_email_sub.unsubscribed_at.blank? : false
      tj_email_subbed = user&.is_member
      compare_fields(
        sync_type,
        [ id_email_subbed ],
        [ tj_email_subbed ],
        Proc.new { get_id_change_date(member, :email_subscription, id_email_sub&.updated_at || member&.updated_at) },
        Proc.new { user_updated_at },
        Proc.new {
          member_hash[:subscriptions] = [] unless member_hash.has_key?(:subscriptions)
          member_hash[:subscriptions].push({
            id: Settings.tijuana.email_subscription_id,
            action: tj_email_subbed ? 'subscribe' : 'unsubscribe'
          })
        },
        Proc.new { tj_changes[:is_member] = id_email_subbed }
      )

      # Compare subscription to SMS.
      id_sms_sub = member&.member_subscriptions&.find_by(subscription_id: Settings.tijuana.sms_subscription_id)
      id_sms_subbed = id_sms_sub ? id_sms_sub&.unsubscribed_at.blank? : false
      tj_sms_subbed = user&.is_member && !user&.do_not_sms
      compare_fields(
        sync_type,
        [ id_sms_subbed ],
        [ tj_sms_subbed ],
        Proc.new { get_id_change_date(member, :sms_subscription, id_sms_sub&.updated_at || member&.updated_at) },
        Proc.new { user_updated_at },
        Proc.new {
          member_hash[:subscriptions] = [] unless member_hash.has_key?(:subscriptions)
          member_hash[:subscriptions].push({
            id: Settings.tijuana.sms_subscription_id,
            action: tj_sms_subbed ? 'subscribe' : 'unsubscribe'
          })
        },
        Proc.new { tj_changes[:do_not_sms] = !id_sms_subbed }
      )

      # Compare subscription to calling.
      id_calling_sub = member&.member_subscriptions&.find_by(subscription_id: Settings.tijuana.calling_subscription_id)
      id_calling_subbed = id_calling_sub ? id_calling_sub&.unsubscribed_at.blank? : false
      tj_calling_subbed = user&.is_member && !user&.do_not_call
      compare_fields(
        sync_type,
        [ id_calling_subbed ],
        [ tj_calling_subbed ],
        Proc.new { get_id_change_date(member, :calling_subscription, id_calling_sub&.updated_at || member&.updated_at) },
        Proc.new { user_updated_at },
        Proc.new {
          member_hash[:subscriptions] = [] unless member_hash.has_key?(:subscriptions)
          member_hash[:subscriptions].push({
            id: Settings.tijuana.calling_subscription_id,
            action: tj_calling_subbed ? 'subscribe' : 'unsubscribe'
          })
        },
        Proc.new { tj_changes[:do_not_call] = !id_calling_subbed }
      )

      # Compare "deceased" flag/tag.
      id_deceased_field = find_custom_field(member&.id || 0, 'deceased')
      id_deceased = id_deceased_field&.data == 'true'
      tj_deceased = !user.nil? && user.has_tag('deceased')
      compare_fields(
        sync_type,
        [ id_deceased ],
        [ tj_deceased ],
        Proc.new { get_id_change_date(member, :deceased, id_deceased_field&.updated_at || member&.updated_at) },
        Proc.new { user_updated_at }, # TODO: Use taggings table updated_at?
        Proc.new {
          member_hash[:custom_fields] = [] unless member_hash.keys.include?(:custom_fields)
          member_hash[:custom_fields].push({
            name: 'deceased',
            value: tj_deceased ? 'true' : 'false'
          })
        },
        Proc.new { tj_changes[:deceased] = id_deceased }
      )

      # Compare "rts" flag/tag.
      id_rts_field = find_custom_field(member&.id || 0, 'rts')
      id_rts = id_rts_field&.data == 'true'
      tj_rts = !user.nil? && user.has_tag('rts')
      compare_fields(
        sync_type,
        [ id_rts ],
        [ tj_rts ],
        Proc.new { get_id_change_date(member, :rts, id_rts_field&.updated_at || member&.updated_at) },
        Proc.new { user_updated_at }, # TODO: Use taggings table updated_at?
        Proc.new {
          member_hash[:custom_fields] = [] unless member_hash.keys.include?(:custom_fields)
          member_hash[:custom_fields].push({
            name: 'rts',
            value: tj_deceased ? 'true' : 'false'
          })
        },
        Proc.new { tj_changes[:rts] = id_rts }
      )

      # puts "########## member_hash = #{member_hash.inspect}"
      # puts "########## tj_changes = #{tj_changes.inspect}"

      unless member_hash.empty?
        begin
          fields_updated = member_hash.keys.dup
          member_hash[:firstname] = member&.first_name unless member_hash.key?(:firstname) # Required param
          member_hash[:lastname] = member&.last_name unless member_hash.key?(:lastname) # Required param
          member_hash[:external_ids] = { tijuana: user&.id } # Needed for lookup
          member_hash[:emails] = [{email: user&.email}] if sync_type == :merge # Needed for lookup
          member_hash[:apply_email_address_changes] = true # Ensure email address changes are honored
          member_hash[:ignore_phone_number_match] = true # Don't match by phone number, too error-prone

          new_member = UpsertMember.call(
            member_hash,
            entry_point: 'tijuana:fetch_updated_users',
            ignore_name_change: false
          )

          if new_member.present?
            if member.blank?
              new_member.created_at = user&.created_at  # Preserve TJ creation date
              new_member.save
              member = new_member
              Rails.logger.info("ID member #{member.id} created from TJ user #{user&.id}")
            else
              Rails.logger.info("ID member #{member.id} updated from TJ user #{user&.id}: #{fields_updated.join(' ')}")
            end
          end
        rescue Exception => e
          Rails.logger.error "Tijuana member sync id:#{user.id}, error: #{e.message}"
          raise
        end
      end

      unless tj_changes.empty?
        user_created = false
        if user.blank?
          if tj_changes[:email].blank?
            Rails.logger.warn("Member #{member&.id} has no email address and cannot be synchronized to TJ")
            return
          end
          user = User.new
          user.created_at = member&.created_at  # Preserve ID creation date
          user_created = true
        end
        fields_updated = tj_changes.keys.dup
        tj_changes.each do |key, value|
          case key
          when :email
            if value.blank?
              Rails.logger.warn("Member #{member&.id}, cannot erase the email address of an existing TJ user")
              next
            else
              user.write_attribute(key, value)
            end
          when :postcode
            user.postcode = Postcode.find_by(number: value)
          when :state
            # State is derived from the postcode in TJ, so it can't mirror any changes made in ID!
            fields_updated.delete(key)
          when :country
            user.write_attribute(:country_iso, value.nil? ? nil : value[0..1])
          when :deceased, :rts
            tag = Tag.find_by(name: key) || Tag.create(name: key)
            if value
              Tagging.create(tag: tag, taggable_type: 'User', taggable_id: user.id)
            else
              user.taggings.where(tag: tag).destroy_all
            end
          else
            user.write_attribute(key, value)
          end
        end
        if user_created
          user.save
          MemberExternalId.create(member: member, system: 'tijuana', external_id: user.id) if user_created
          Rails.logger.info("TJ user #{user.id} created from ID member #{member&.id}")
        elsif fields_updated.count > 0
          user.save
          Rails.logger.info("TJ user #{user.id} updated from ID member #{member&.id}: #{fields_updated.join(' ')}")
        end
      end
    end

    def self.find_custom_field(member_id, key)
      CustomField.joins(:custom_field_key).where('member_id = ? and custom_field_keys.name = ?', member_id, key).first
    end

    def self.has_tag(user, tag_name)
      user.nil? ? false : user.tags.where(name: tag_name).first != nil
    end

    def self.standardise_phone_number(phone_number)
      begin
        if phone_number.present?
          standardised_number = PhoneNumber.standardise_phone_number(phone_number)
          # Temporary workaround to forestall problems created by ID's current
          # handling of some bad phone numbers. A call made to Phony.split
          # during ID's member upsert throws an error in these cases. To avoid
          # this happening, we catch these cases ourselves before the upsert,
          # and abandon trying to upsert the affected number.
          Phony.split(standardised_number)
          standardised_number
        else
          nil
        end
      rescue => e
        Rails.logger.warn "#{e.class.name} occurred while standardising phone number #{phone_number}"
        nil
      end
    end
  end
end