module IdentityTijuana
  # TODO add AnonymisationLog in TJ
  class UserGhosting
    def initialize(user_ids, reason)
      @user_ids = user_ids
      @reason = reason
    end

    def ghost_users
      tj_conn = IdentityTijuana::ReadWrite.connection
      # log_ids = log_anonymisation_started
      begin
        tj_conn.transaction do
          anon_basic_info(tj_conn)
          # anon_automation_events(tj_conn)
          # anon_call_outcomes(tj_conn)
          # anon_comments(tj_conn)
        end
      rescue ActiveRecord::RecordInvalid => e
        # log_anonymisation_failed(log_ids, e.message, e)
        Rails.logger.error "Anonymisation failed: #{e.message}"
      end

      # log_anonymisation_finished(log_ids)
    end

    private

    def log_anonymisation_started
      log_ids = []

      @user_ids.each do |user_id|
        logged = AnonymisationLog.create!(
          user_id: user_id,
          reason: @reason,
          status: 'started',
          started_at: DateTime.current.utc,
        )
        log_ids << logged.id
      end

      log_ids
    end

    def log_anonymisation_finished(log_ids)
      # rubocop:disable Rails/SkipsModelValidations
      AnonymisationLog.where(id: log_ids)
                      .update_all(
                        finished_at: DateTime.current.utc,
                        status: 'completed'
                      )
      # rubocop:enable Rails/SkipsModelValidations
    end

    def log_anonymisation_failed(log_ids, error_msg, error_stack)
      # rubocop:disable Rails/SkipsModelValidations
      AnonymisationLog.where(id: log_ids)
                      .update_all(
                        finished_at: DateTime.current.utc,
                        status: 'failed',
                        message: error_msg,
                        error_stack: error_stack
                      )
      # rubocop:enable Rails/SkipsModelValidations
    end

    def anon_basic_info(tj_conn)
      tj_conn.execute(<<~SQL.squish)
        UPDATE users
        SET email = concat(id, '@#{Settings.ghoster.email_domain}'),
            first_name = null,
            last_name = null,
            mobile_number = null,
            home_number = null,
            street_address = null,
            country_iso = null,
            is_member = 0,
            encrypted_password = null,
            password_salt = null,
            reset_password_token = null,
            remember_created_at = null,
            sign_in_count = 0,
            current_sign_in_at = null,
            last_sign_in_at = null,
            current_sign_in_ip = null,
            last_sign_in_ip = null,
            is_admin = 0,
            postcode_id = null,
            old_tags = '',
            is_volunteer = 0,
            random = null,
            notes = null,
            quick_donate_trigger_id = null,
            facebook_id = null,
            otp_secret_key = null,
            tracking_token = null,
            do_not_call = 1,
            active = 0,
            do_not_sms = 1,
            updated_at = CURRENT_TIMESTAMP
          WHERE id IN (#{@user_ids.join(',')});
      SQL
    end
    # FIX
    # exist in production but missing in testing db
    # -- new_tags = null,
    # -- fragment = null,
    # mautic_id = null,

    def anon_automation_events(tj_conn)
      tj_conn.execute(<<~SQL.squish)
        UPDATE automation_events
        SET payload = null
        WHERE id IN (#{@user_ids.join(',')});
      SQL
    end

    def anon_call_outcomes(tj_conn)
      tj_conn.execute(<<~SQL.squish)
        UPDATE call_outcomes
        SET email = null,
            payload = null,
            dialed_number = null
        WHERE id IN (#{@user_ids.join(',')});
      SQL
    end

    def anon_comments(tj_conn)
      tj_conn.execute(<<~SQL.squish)
        UPDATE comments
        SET body = null,
            dialed_number = null,
            updated_at = CURRENT_TIMESTAMP
        WHERE id IN (#{@user_ids.join(',')});
      SQL
    end
  end
end
