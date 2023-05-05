module IdentityTijuana
  class Blast < ReadWrite
    self.table_name = 'blasts'
    belongs_to :push
    has_many :emails

    scope :deleted_blasts, -> (last_updated_at, exclude_from) {
      where(%{
        deleted_at is not null
        and deleted_at >= ?
        and deleted_at < ?
      },
      last_updated_at, exclude_from
      ).order('deleted_at, id')
    }

    scope :updated_blasts, -> (last_updated_at, last_id, exclude_from) {
      updated_blasts_all(last_updated_at, last_id, exclude_from)
        .order('updated_at, id')
        .limit(Settings.tijuana.pull_batch_amount)
    }

    scope :updated_blasts_all, -> (last_updated_at, last_id, exclude_from) {
      where(%{
        deleted_at is null and (
          ((updated_at > ? or (updated_at = ? and id > ?)) and updated_at < ?)
          or id in (
            select blast_id
            from emails
            where (updated_at >= ? and updated_at < ?)
            or (deleted_at >= ? and deleted_at < ?)
          )
        )
      },
      last_updated_at, last_updated_at, last_id, exclude_from,
      last_updated_at, exclude_from,
      last_updated_at, exclude_from
      )
    }

    def import(sync_id)
      begin
        subject_line_count = emails.count('distinct subject')
        body_count = emails.count('distinct body')

        mailing = ::Mailings::Mailing.find_or_create_by(external_id: self.id.to_s, external_source: 'tijuana')
        mailing.name = self.name
        mailing.subject = (subject_line_count > 1) ? '{{subject_line}}' : emails.first&.subject
        mailing.body_html = (body_count > 1) ? '{{body}}' : emails.first&.body
        # mailing.body_plain = nil
        mailing.from = emails.first&.from_address
        # mailing.recipients_synced = nil
        # mailing.member_count = nil
        # mailing.parsed_html = nil
        # mailing.mailing_template_id = nil
        # mailing.list_id = nil
        # mailing.send_time = nil
        # mailing.prepared_send_at = nil
        # mailing.total_opens = nil
        # mailing.total_clicks = nil
        # mailing.from_name = nil
        # mailing.from_email = nil
        # mailing.total_spam_reports = nil
        # mailing.total_bounces = nil
        # mailing.finished_sending_at = nil
        # mailing.total_unsubscribes = nil
        # mailing.scheduled_for = nil
        # mailing.priority = nil
        # mailing.processed_count = nil
        # mailing.aborted = nil
        # mailing.recurring = nil
        # mailing.recurring_max_recipients_per_send = nil
        # mailing.search_id = nil
        # mailing.parent_mailing_id = nil
        # mailing.body_markdown = nil
        # mailing.recurring_schedule = nil
        # mailing.recurring_at = nil
        # mailing.recurring_day = nil
        # mailing.recurring_last_run_started = nil
        # mailing.paused = nil
        # mailing.is_controlled_externally = nil
        # mailing.external_slug = nil
        # mailing.total_actions = nil
        # mailing.total_donate_amount = nil
        # mailing.total_donate_count = nil
        # mailing.total_reg_donate_amount = nil
        # mailing.total_reg_donate_count = nil
        # mailing.started_send_at = nil
        # mailing.cloned_mailing_id = nil
        # mailing.prepared_count = nil
        # mailing.reply_to = nil
        # mailing.quiet_send = nil
        # mailing.renderer = nil
        # mailing.archived_subject = nil
        # mailing.archived_body = nil
        mailing.campaign = ::Campaign.find_by(external_id: self.push_id.to_s, external_source: 'tijuana_push')
        mailing.save!

        mailing.tests.destroy_all

        if subject_line_count > 1
          subject_line_mailing_test = Mailings::MailingTest.find_or_create_by(mailing: mailing, merge_tag: 'subject_line')
          subject_line_mailing_test.name = 'Tijuana subject line test'
          subject_line_mailing_test.mailing = mailing
          subject_line_mailing_test.save!
        else
          subject_line_mailing_test = nil
        end

        if body_count > 1
          body_mailing_test = Mailings::MailingTest.find_or_create_by(mailing: mailing, merge_tag: 'body')
          body_mailing_test.name = 'Tijuana email body test'
          body_mailing_test.mailing = mailing
          body_mailing_test.save!
        else
          body_mailing_test = nil
        end

        emails.each do |email|
          mailing_variation = ::Mailings::MailingVariation.find_by(external_id: self.id.to_s, external_source: 'tijuana')
          if mailing_variation.blank?
            mailing_variation = ::Mailings::MailingVariation.create(
              mailing: mailing,
              external_id: self.id.to_s,
              external_source: 'tijuana'
            )
          else
            mailing_variation.mailing = mailing
          end
          # mailing_variation.total_opens = nil
          # mailing_variation.total_clicks = nil
          # mailing_variation.total_members = nil
          # mailing_variation.total_actions = nil
          # mailing_variation.donate_amount = nil
          # mailing_variation.reg_donate_amount = nil
          # mailing_variation.reg_donate_count = nil
          mailing_variation.save!
          if subject_line_mailing_test.present?
            subject_line_mailing_test_case = Mailings::MailingTestCase.find_or_create_by(
              mailing_test: subject_line_mailing_test,
              template: email.subject
            )
            Mailings::MailingVariationTestCase.find_or_create_by(
              mailing_variation: mailing_variation,
              mailing_test_case: subject_line_mailing_test_case
            )
          end
          if body_mailing_test.present?
            body_mailing_test_case = Mailings::MailingTestCase.find_or_create_by(
              mailing_test: body_mailing_test,
              template: email.body
            )
            Mailings::MailingVariationTestCase.find_or_create_by(
              mailing_variation: mailing_variation,
              mailing_test_case: body_mailing_test_case
            )
          end
        end
      rescue Exception => e
        Rails.logger.error "Tijuana blasts sync id:#{self.id}, error: #{e.message}"
        raise
      end
    end

    def erase(sync_id)
      begin
        mailing = ::Mailings::Mailing.find_by(external_id: self.id.to_s, external_source: 'tijuana')
        if mailing.present?
          mailing.tests.destroy_all
          mailing.destroy
        end
      rescue Exception => e
        Rails.logger.error "Tijuana blasts delete id:#{self.id}, error: #{e.message}"
        raise
      end
    end
  end
end
