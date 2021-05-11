module ExternalSystems::IdentityTijuana
  EMAIL_ACTIVITIES = [
    [:created_at, 'email_sent'],
    [:first_opened, 'email_viewed'],
    [:first_clicked, 'email_clicked'],
  ]

  class Push < ApplicationRecord
    include ReadWrite
    self.table_name = 'pushes'

    belongs_to :campaign
    has_many :blasts

    def create_activities_table
      raise RuntimeError if self.id.blank?
      create_table_sql = "CREATE TABLE IF NOT EXISTS `push_#{self.id}` (
`user_id` int(11) NOT NULL,
`activity` varchar(64) NOT NULL,
`email_id` int(11) NOT NULL,
`created_at` DATETIME,
KEY `activity_idx` (`activity`),
KEY `email_idx` (`email_id`),
KEY `user_idx` (`user_id`),
KEY `user_activity_idx` (`user_id`,`activity`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;"
    self.class.connection.execute(create_table_sql)
    end

    def self.export(mailing_id)
      mailing = Mailer::Mailing.find(mailing_id)

      push = Push.create!(campaign_id: nil, name: mailing.name)
      blast = Blast.create!(push_id: push.id, name: mailing.name)
      email_hash = {
        blast_id: blast.id,
        name: mailing.subject,
        from_address: mailing.from_email,
        from_name: mailing.from_name,
        subject: mailing.subject,
        body: mailing.body_html,
      }

      email = Email.create!(email_hash)

      push.create_activities_table

      #Mailer::Mailing.external_id = push.id
      #Mailer::Mailing.save!()
    end

    def self.export_member_mailings(member_mailing_id)
      member_mailing = MemberMailing.find(member_mailing_id)
      push = Push.find(member_mailing.mailing.external_id)

      user_push_hash = {
        user_id: User.from_member(member_mailing.member).id,
        email_id: push.blasts.first.email.id, 
      }

      EMAIL_ACTIVITIES.each do |attribute, activity|
        user_push_hash.activity = activity
        user_push_hash.created_at = member_mailing[attribute]
        user_push_hash.updated_at = member_mailing[attribute]

        # Save in push table
        insert_sql = "INSERT INTO push_? (user_id, activity, email_id, created_at, updated_at) VALUES (?, ?, ?, ?);"
        execute_escaped insert_sql, push.id, user_push_hash.user_id, activity, user_push_hash.email_id, user_push_hash.created_at, user_push_hash.updated_at  
      end
    end
  end
end
