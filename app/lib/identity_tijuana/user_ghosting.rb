module IdentityTijuana
  class UserGhosting
    def initialize(user_ids, reason)
      @user_ids = user_ids
      @reason = reason
    end

    def ghost_users
      # We must never ghost member that has active recurring donations
      recurring_donations = Donation.where(
        user_id: @user_ids,
        active: true,
        cancelled_at: nil
      ).where.not(
        frequency: 'one-off'
      ).where.not(
        make_recurring_at: nil
      )

      if recurring_donations.any?
        recurring_user_ids = recurring_donations.pluck(:user_id)

        Rails.logger.error(
          "Members [ids: #{recurring_user_ids.join(', ')}] " \
          "with active recurring donations cannot be anonymised! " \
          "Please notify Member Relations Team."
        )

        @user_ids -= recurring_user_ids
      end

      if @user_ids.empty?
        Rails.logger.error "No member ids provided to anonymise."
        return
      end

      tj_conn = IdentityTijuana::ReadWrite.connection
      log_ids = log_anonymisation_started
      @emails = get_emails(tj_conn)

      begin
        tj_conn.transaction do
          anon_basic_info(tj_conn)
          anon_call_outcomes(tj_conn)
          anon_donations(tj_conn)
          anon_facebook_users(tj_conn)
          anon_merge_records(tj_conn)
          anon_image_shares(tj_conn)
          anon_petition_signatures(tj_conn)
          anon_testimonials(tj_conn)
          anon_user_emails(tj_conn)
          anon_user_activity_events(tj_conn)
        end
      rescue ActiveRecord::RecordInvalid => e
        log_anonymisation_failed(log_ids, e.message, e)
        Rails.logger.error "Anonymisation failed: #{e.message}"
      end

      log_anonymisation_finished(log_ids)
    end

    private

    def get_emails(tj_conn)
      res = tj_conn.select_all(<<~SQL.squish)
        SELECT email
        FROM users
        WHERE id IN (#{@user_ids.join(',')});
      SQL

      res.pluck('email')
    end

    def log_anonymisation_started
      log_ids = []

      @user_ids.each do |user_id|
        logged = AnonymisationLog.create!(
          user_id: user_id,
          anonymisation_reason: @reason,
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
            current_sign_in_ip = null,
            last_sign_in_ip = null,
            is_admin = 0,
            postcode_id = null,
            quick_donate_trigger_id = null,
            facebook_id = null,
            otp_secret_key = null,
            do_not_call = 1,
            active = 0,
            do_not_sms = 1,
            updated_at = CURRENT_TIMESTAMP
          WHERE id IN (#{@user_ids.join(',')});
      SQL
    end

    def anon_call_outcomes(tj_conn)
      tj_conn.execute(<<~SQL.squish)
        UPDATE call_outcomes
        SET email = null,
            donation_email = null,
            payload = null,
            dialed_number = null
        WHERE user_id IN (#{@user_ids.join(',')});
      SQL
    end

    def anon_donations(tj_conn)
      tj_conn.execute(<<~SQL.squish)
        UPDATE donations
        SET name_on_card = null,
            cheque_name = null,
            identifier = null,
            dynamic_attributes = null,
            updated_at = CURRENT_TIMESTAMP
        WHERE user_id IN (#{@user_ids.join(',')});
      SQL
    end

    def anon_facebook_users(tj_conn)
      tj_conn.execute(<<~SQL.squish)
        UPDATE facebook_users
        SET facebook_id = null,
            updated_at = CURRENT_TIMESTAMP
        WHERE user_id IN (#{@user_ids.join(',')});
      SQL
    end

    def anon_merge_records(tj_conn)
      sql = ActiveRecord::Base.sanitize_sql_array(["
         UPDATE merge_records
         SET join_id = NULL, `value` = NULL, updated_at = CURRENT_TIMESTAMP
         WHERE `value` IN (?) OR join_id IN (?)
         ", @emails, @emails])

      tj_conn.execute(sql)
    end

    def anon_image_shares(tj_conn)
      tj_conn.execute(<<~SQL.squish)
        UPDATE image_shares
        SET caption = '',
            updated_at = CURRENT_TIMESTAMP
        WHERE user_id IN (#{@user_ids.join(',')});
      SQL
    end

    def anon_petition_signatures(tj_conn)
      tj_conn.execute(<<~SQL.squish)
        UPDATE petition_signatures
        SET dynamic_attributes = null,
            updated_at = CURRENT_TIMESTAMP
        WHERE user_id IN (#{@user_ids.join(',')});
      SQL
    end

    def anon_testimonials(tj_conn)
      tj_conn.execute(<<~SQL.squish)
        UPDATE testimonials
        SET facebook_user_id = null,
            updated_at = CURRENT_TIMESTAMP
        WHERE user_id IN (#{@user_ids.join(',')});
      SQL
    end

    def anon_user_activity_events(tj_conn)
      tj_conn.execute(<<~SQL.squish)
        UPDATE user_activity_events
        SET public_stream_html = null,
            updated_at = CURRENT_TIMESTAMP
        WHERE user_id IN (#{@user_ids.join(',')});
      SQL
    end

    def anon_user_emails(tj_conn)
      tj_conn.execute(<<~SQL.squish)
        UPDATE user_emails
        SET body = '',
            `from` = '',
            updated_at = CURRENT_TIMESTAMP
        WHERE user_id IN (#{@user_ids.join(',')});
      SQL
    end
  end
end
