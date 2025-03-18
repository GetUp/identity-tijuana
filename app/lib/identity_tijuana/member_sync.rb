module IdentityTijuana
  class MemberSync
    # Sync an ID member with TJ.
    def self.export_member(member, sync_id)
      sync_type = :unknown
      begin
        return if member.ghosting_started?

        # Destroy any dangling external ID references, remove any
        # external ids from the list if not found
        ext_ids = MemberExternalId.where(
          system: 'tijuana',
          member: member
        ).select do |ext_id|
          user = User.find_by(id: ext_id.external_id.to_i)
          if user.nil?
            Rails.logger.info(
              "[IdentityTijuana::export_member]: " \
              "Removing dangling external id for Id member #{member.id}, " \
              "TJ user #{ext_id.external_id} " \
              "(sync_id=#{sync_id}, sync_type=#{sync_type}, " \
              "sync_direction=export_member)"
            )
            ext_id.destroy!
          end
          user.present? # return value for `select` call
        end
        if ext_ids.count == 0
          # XXX this will fail for de-normalised and/or cleaned emails
          user = User.find_by(email: member.email) if member.email.present?

          if user.nil?
            sync_type = :create
          else
            sync_type = :merge
            Rails.logger.info(
              "[IdentityTijuana::export_member]: " \
              "Adding external id for Id member #{member.id} " \
              "to TJ user #{user.id} " \
              "(sync_id=#{sync_id}, sync_type=#{sync_type}, " \
              "sync_direction=export_member)"
            )
            MemberExternalId.create!(
              system: 'tijuana',
              member: member,
              external_id: user.id.to_s
            )
          end
        else
          # Only the primary match gets synced. Others should be
          # linked, but not synced.
          user = find_primary_user_for_member(member)
          sync_type = :update
        end

        sync(user, member, sync_type, sync_id, :export_member)
      rescue StandardError => e
        Rails.logger.error "[IdentityTijuana::export_member] failed: " \
                           "#{e.message} member_id=#{member.id}" \
                           "(sync_id=#{sync_id}, sync_type=#{sync_type}, " \
                           "sync_direction=export_member)"
        raise e
      end
    end

    # Sync a TJ user with ID.
    def self.import_user(user_id, sync_id)
      sync_type = :unknown
      begin
        user = User.find(user_id)
        member = Member.find_by_external_id(:tijuana, user_id)

        if member.blank?
          # Didn't find an existing, alredy-linked member, so look for
          # one that exists but is not yet linked. If found, add the
          # link so the sync implementation can determine the correct
          # primary TJ user when the member found already has other
          # linked users (i.e. this user might not be the primary).
          #
          # In particular, the Cleanser may return an email that is
          # not the same as this user's email, e.g. typos like
          # "alice@gmail.co" will be returned as "alice@gmail.com". So
          # a typo'ed TJ user may be getting added to an existing Id
          # member already linked to another TJ user without the typo
          cleansed_email = Cleanser.cleanse_email(user.email)
          member = Member.find_by(email: cleansed_email) if cleansed_email.present?

          if member.nil?
            sync_type = :create
          else
            sync_type = :merge
            Rails.logger.info "[IdentityTijuana::import_user] " \
                              "Adding external id for TJ user #{user_id} " \
                              "to Id member #{member.id}" \
                              "(sync_id=#{sync_id}, sync_type=#{sync_type}, " \
                              "sync_direction=import_user)"
            MemberExternalId.create!(
              system: 'tijuana',
              member: member,
              external_id: user.id.to_s
            )
          end
        else
          sync_type = :update
        end

        if member.present?
          if member.ghosting_started?
            Rails.logger.error "[IdentityTijuana::import_user] " \
                               "Member #{member.id} for TJ user #{user_id} is " \
                               "ghosted, not updating " \
                               "(sync_id=#{sync_id}, sync_type=#{sync_type}, " \
                               "sync_direction=import_user)"
            return
          end

          primary_user = find_primary_user_for_member(member)
          if primary_user.id != user_id
            # Only the primary match gets synced. Others should be
            # linked, but not synced.
            Rails.logger.info "[IdentityTijuana::import_user] " \
                              "TJ user #{user_id} not primary for " \
                              "Id member #{member.id}, not syncing " \
                              "(sync_id=#{sync_id}, sync_type=#{sync_type}, " \
                              "sync_direction=import_user)"
            return
          end
        end

        sync(user, member, sync_type, sync_id, :import_user)
      rescue StandardError => e
        Rails.logger.error "[IdentityTijuana::import_user] failed: " \
                           "#{e.message} user_id=#{user_id}" \
                           "(sync_id=#{sync_id}, sync_type=#{sync_type}, " \
                           "sync_direction=import_user)"
        raise e
      end
    end

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
    }.freeze

    # Find the primary TJ user match for a given ID member.
    #
    # Looks at the user for each given id, orders them by created at
    # date, then selects:
    #
    #  1. The user with a normalised (but not cleaned), matching email, if any
    #  2. The first subscribed user, if any
    #  3. The first remaining user
    def self.find_primary_user_for_member(member)
      external_ids = member.member_external_ids.where(system: 'tijuana')
      if external_ids.nil? || external_ids.count == 0
        raise "Id member has no linked TJ users"
      end

      # Some scenarios to think about before changing this:
      #
      # (1) A member email address may not match a TJ user email
      # address. This could be because of:
      #    * The cleaner fixed a typo
      #    * Un-normalised data in both (example@gmail.com vs
      #      Exam.ple@gmail.com
      #    * The member's email was changed through Id CRM UI
      #
      # (1) A member's email address changed in Id, as a result no
      # associated TJ users have the same email address.
      #
      # (2) A member subscribes and becomes active. They then typo
      # their email when signing a petition from a new browser. The
      # newer typo'ed user is not yet active (although it will become
      # active tomorrow morning) but it is subscribed.
      #
      # (3) A member has two users associated with it, one with the
      # correct email and one with a typo. The typo'ed user gets
      # updated because they sign another petition with the same typo
      # and a new postcode.
      #
      # (4) A member subscribes using a typo'ed email, becomes active
      # since they are a new member but unsubscribed because their
      # email bounced. Their Id member record has the correct email
      # because the Cleanser fixed it. Thus the member and associated
      # user have different email addresses. The member later signs
      # another petition using the correct email address.

      # The points above means that we should matching based on email
      # first if present, otherwise fall back looking at subscribed
      # users, then users that first created (assuming most members
      # will likely not typo their email address).
      #
      # In particular we can't rely on most-recently-updated, since
      # typo'ed users can still get updated because of (3) above. We
      # also can't rely on active, since it's laggy but also typo'ed
      # users can be active after they first sign up.

      ext_ids = external_ids.map { |id| id.external_id.to_i }
      users = User.where(id: ext_ids).order(created_at: :asc)
      if users.count != external_ids.count
        raise "Not enough matching users for external ids: #{ext_ids}"
      end

      matching_emails = users.select { |user|
        # Need to normalise the email to match the normalisation Id
        # would do, but as-is, i.e. without any typo correction. So
        # `example@gmail.com` should match `EXAMPLE@GMAIL.COM` but not
        # `example@gamil.com` (note the typo).
        Cleanser.normalise_email(user.email) == member.email
      }

      primary = matching_emails.first

      if primary.nil?
        subscribed_users = users.select { |user| user.is_member }
        primary = subscribed_users.first
      end

      if primary.nil?
        primary = users.first
      end

      primary
    end

    # Use the audit log to work out the date/time a given field or set of
    # fields was last changed in ID.
    def self.get_id_change_date(member, field_info_type, default_change_date = nil)
      # Default change date to the epoch if not passed, or if passed as nil.
      default_change_date = Time.zone.at(0) if default_change_date.nil?
      # Must have a member to search against!
      return default_change_date if member.nil?

      # Pull parameters to drive the audit log search.
      audit_list_name, auditable_type, audit_field_names = AUDIT_SEARCH_PARAMS[field_info_type]
      # Check whether we have an ancillary matching field.
      ancillary_match_value = nil
      case auditable_type
      when 'Address'
        # Temporary workaround to retrieve the actual `updated_at` timestamp
        # of the model, instead of getting it via audit logs.
        # The reason for this is that we are `touching` member addresses
        # to `mark` them as primary, and this cannot be picked from the audit
        # logs as currently it is not a tracked attribute. Thus the change
        # will be overriden during the `import` sync from TJ.
        return default_change_date if default_change_date
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
      # Note that we use `reorder` to remove all prior ordering clauses.
      # ActiveRecordAudit automatically applies `ORDER BY version ASC` when the `order`
      # method is used. While we could override this with `order(version: :desc)`,
      # using `reorder` with `created_at: :desc` is better aligned in terms
      # "iterating backwards in time" through the audit logs.
      # Additionally, `created_at` is an indexed column as opposed to `version`.
      member.send(audit_list_name)
            .where(auditable_type: auditable_type)
            .reorder(created_at: :desc)
            .each do |audit|
        # Check ancillary matching field, where required.
        if !ancillary_match_value.nil?
          case auditable_type
          when 'PhoneNumber'
            phone_number_type =
              audit.audited_changes['phone_type'] ||
              PhoneNumber.find_by(id: audit.auditable_id).try(:phone_type)

            # The audited_changes for `phone_type` may contain an array, eg.
            # ["mobile", "landline"] if the phone type was updated –
            # and which did happen in the past.
            # The array represents [old_value, new_value].
            if audit.action == 'update' && phone_number_type.kind_of?(Array)
              phone_number_type = phone_number_type[1]
            end
            next unless phone_number_type.to_sym == ancillary_match_value
          when 'MemberSubscription'
            audit_subscription_id =
              audit.audited_changes['subscription_id'] ||
              MemberSubscription.find_by(id: audit.auditable_id).try(:subscription_id)
            next unless audit_subscription_id.to_i == ancillary_match_value.to_i
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
      id_vals = id_field_values.map { |e| e == '' ? nil : e }
      tj_vals = tj_field_values.map { |e| e == '' ? nil : e }
      return if id_vals == tj_vals

      id_val_count = id_vals.count { |element| !element.nil? }
      tj_val_count = tj_vals.count { |element| !element.nil? }
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
          conflicts = id_vals.zip(tj_vals).sum { |i, t| !i.nil? && !t.nil? && i != t ? 1 : 0 }
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
    def self.sync(user, member, sync_type, sync_id, sync_direction)
      member_hash = {}
      tj_changes = {}
      user_updated_at = user&.updated_at || Time.zone.at(0)

      # Compare first & last names.
      compare_fields(
        sync_type,
        [member&.first_name, member&.last_name],
        [user&.first_name, user&.last_name],
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
      #
      # Note that UpsertService will call Cleanser.cleanse_email on
      # any email that gets passed through to it, so cleanse TJ user's
      # email up front to see if it's worth doing.
      compare_fields(
        sync_type,
        [member&.email], # Id normalises its email addresses, so this is clean
        [Cleanser.cleanse_email(user&.email)], # TJ does not, so scrub it
        Proc.new { get_id_change_date(member, :email, member&.updated_at) },
        Proc.new { user_updated_at },
        Proc.new {
          # Don't need to scrub TJ user email here, UpsertService will
          # do it for us if needed
          member_hash[:emails] = [{ email: user.email }]
        },
        Proc.new { tj_changes[:email] = member.email }
      )

      # Compare mobile number.
      id_mobile = member&.phone_numbers&.mobile&.first
      id_mobile_number = id_mobile&.phone
      tj_mobile_number = standardise_phone_number(user&.mobile_number)
      compare_fields(
        sync_type, [id_mobile_number], [tj_mobile_number],
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
        sync_type, [id_landline_number], [tj_landline_number],
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
        [member_address&.line1, member_address&.line2, member_address&.town,
         member_address&.country, member_address&.state, member_address&.postcode],
        [user&.street_address, nil, user&.suburb,
         user&.country_iso, user_postcode&.state, user_postcode&.number],
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
        [id_email_subbed],
        [tj_email_subbed],
        Proc.new { get_id_change_date(member, :email_subscription, id_email_sub&.updated_at || member&.updated_at) },
        Proc.new { user_updated_at },
        Proc.new {
          member_hash[:subscriptions] = [] unless member_hash.has_key?(:subscriptions)
          member_hash[:subscriptions].push({
                                             id: Settings.tijuana.email_subscription_id,
                                             action: tj_email_subbed ? 'subscribe' : 'unsubscribe',
                                             reason: 'tijuana'
                                           })
        },
        Proc.new {
          tj_changes[:is_member] = id_email_subbed
          tj_changes[:reason] = id_email_subbed ? id_email_sub&.unsubscribe_reason : id_email_sub&.subscribe_reason
        }
      )

      # Compare subscription to SMS.
      id_sms_sub = member&.member_subscriptions&.find_by(subscription_id: Settings.tijuana.sms_subscription_id)
      id_sms_subbed = id_sms_sub ? id_sms_sub&.unsubscribed_at.blank? : false
      tj_sms_subbed = user&.is_member && !user&.do_not_sms
      compare_fields(
        sync_type,
        [id_sms_subbed],
        [tj_sms_subbed],
        Proc.new { get_id_change_date(member, :sms_subscription, id_sms_sub&.updated_at || member&.updated_at) },
        Proc.new { user_updated_at },
        Proc.new {
          member_hash[:subscriptions] = [] unless member_hash.has_key?(:subscriptions)
          member_hash[:subscriptions].push({
                                             id: Settings.tijuana.sms_subscription_id,
                                             action: tj_sms_subbed ? 'subscribe' : 'unsubscribe',
                                             reason: 'tijuana'
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
        [id_calling_subbed],
        [tj_calling_subbed],
        Proc.new { get_id_change_date(member, :calling_subscription, id_calling_sub&.updated_at || member&.updated_at) },
        Proc.new { user_updated_at },
        Proc.new {
          member_hash[:subscriptions] = [] unless member_hash.has_key?(:subscriptions)
          member_hash[:subscriptions].push({
                                             id: Settings.tijuana.calling_subscription_id,
                                             action: tj_calling_subbed ? 'subscribe' : 'unsubscribe',
                                             reason: 'tijuana'
                                           })
        },
        Proc.new { tj_changes[:do_not_call] = !id_calling_subbed }
      )

      # puts "########## member_hash = #{member_hash.inspect}"
      # puts "########## tj_changes = #{tj_changes.inspect}"

      # Check for no-op
      if member_hash.empty? && tj_changes.empty?
        if sync_type == :create
          record = sync_direction == :export_member ? "TJ user" : "ID member"
          Rails.logger.error "[IdentityTijuana::sync] failed " \
                             "to create #{record} record" \
                             "(sync_id=#{sync_id}, sync_type=#{sync_type}" \
                             ", sync_direction=#{sync_direction})" \
                             "- #{[member_info, user_info].compact.join(', ')}"
        else
          member_info = "ID: member_id=#{member.id}" if member&.id
          user_info = "TJ: user_id=#{user.id}" if user&.id
          Rails.logger.info "[IdentityTijuana::sync] no changes detected " \
                            "(sync_id=#{sync_id}, sync_type=#{sync_type}" \
                            ", sync_direction=#{sync_direction})" \
                            "- #{[member_info, user_info].compact.join(', ')}"
        end
      end

      unless member_hash.empty?
        fields_updated = member_hash.keys.dup
        member_hash[:firstname] = member&.first_name unless member_hash.key?(:firstname) # Required param
        member_hash[:lastname] = member&.last_name unless member_hash.key?(:lastname) # Required param
        member_hash[:external_ids] = { tijuana: user&.id } # Needed for lookup
        member_hash[:emails] = [{ email: user&.email }] if sync_type == :merge # Needed for lookup
        member_hash[:apply_email_address_changes] = true # Ensure email address changes are honored
        member_hash[:ignore_phone_number_match] = true # Don't match by phone number, too error-prone

        if member_hash.key?(:emails)
          email = member_hash[:emails][0][:email]
          if member.present?
            # Identity does *not* require email addresses to be
            # unique in the database (only from the UI?), so check
            # for it up front and raise an intelligible exception if
            # conflicts found.
            conflicting_members = Member.where(email: email).where.not(id: member.id)
            if conflicting_members.count > 0
              raise "Email conflict: Id members " \
                    "#{conflicting_members.pluck(:id)} already have " \
                    "email address #{email}, bailing out"
            end
          end
        end

        new_member = UpsertMember.call(
          member_hash,
          entry_point: 'tijuana:fetch_updated_users',
          ignore_name_change: false
        )

        if member.blank?
          new_member.created_at = user&.created_at # Preserve TJ creation date
          new_member.save!
          member = new_member
          Rails.logger.info("[IdentityTijuana::sync] ID member #{member.id} created from TJ user #{user&.id} (sync_id=#{sync_id}, sync_type=#{sync_type}, sync_direction=#{sync_direction})")
        else
          Rails.logger.info("[IdentityTijuana::sync] ID member #{member.id} updated from TJ user #{user&.id}: #{fields_updated.join(' ')} (sync_id=#{sync_id}, sync_type=#{sync_type}, sync_direction=#{sync_direction})")
        end
      end

      unless tj_changes.empty?
        user_created = false
        if user.blank?
          if tj_changes[:email].blank?
            Rails.logger.warn("[IdentityTijuana::sync] Member #{member&.id} has no email address and cannot be synchronized to TJ (sync_id=#{sync_id}, sync_type=#{sync_type}, sync_direction=#{sync_direction})")
            return
          end
          user = User.new
          user.created_at = member&.created_at # Preserve ID creation date
          user_created = true
        end

        fields_updated = tj_changes.keys.dup
        tj_changes.each do |key, value|
          case key
          when :email
            if value.blank?
              Rails.logger.warn("[IdentityTijuana::sync] Member #{member&.id} has no email address - cannot erase the email address of an existing TJ user (sync_id=#{sync_id}, sync_type=#{sync_type}, sync_direction=#{sync_direction})")
              next
            else
              # TJ does require email addresses to be unique, but lets
              # check for it up front and raise an intelligible
              # exception if found.
              conflicting_users = User.where(email: value).where.not(id: user.id)
              if conflicting_users.count > 0
                raise "Email conflict: TJ users " \
                      "#{conflicting_users.pluck(:id)} already have " \
                      "email address #{email}, bailing out"
              end
            end
            user.write_attribute(key, value)
          when :postcode
            user.postcode = Postcode.find_by(number: value)
          when :state, :reason
            # For state, since it is derived from the postcode in TJ,
            # it can't mirror any changes made in ID
            fields_updated.delete(key)
          when :country
            user.write_attribute(:country_iso, value.nil? ? nil : value[0..1])
          when :is_member
            user.write_attribute(:is_member, value)
            msg = "#{value ? 'Subscribed' : 'Unsubscribed'} via update from Identity."
            uae = IdentityTijuana::UserActivityEvent.create!(
              :activity => value ? :subscribed : :unsubscribed,
              :user => user,
              :public_stream_html => msg,
            )
            unless value
              IdentityTijuana::Unsubscribe.create!(
                :user => user,
                :specifics => tj_changes[:reason] || msg,
                :created_at => uae.created_at
              )
            end
          else
            user.write_attribute(key, value)
          end
        end

        if user_created
          user.save!
          MemberExternalId.create!(member: member, system: 'tijuana', external_id: user.id)
          Rails.logger.info("[IdentityTijuana::sync] TJ user #{user.id} created from ID member #{member&.id} (sync_id=#{sync_id}, sync_type=#{sync_type}, sync_direction=#{sync_direction})")
        elsif fields_updated.count > 0
          user.save!
          Rails.logger.info("[IdentityTijuana::sync] TJ user #{user.id} updated from ID member #{member&.id}: #{fields_updated.join(' ')} (sync_id=#{sync_id}, sync_type=#{sync_type}, sync_direction=#{sync_direction})")
        end
      end
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
        Rails.logger.warn "[IdentityTijuana::standardise_phone_number] #{e.class.name} occurred while standardising phone number #{phone_number}"
        nil
      end
    end
  end
end
