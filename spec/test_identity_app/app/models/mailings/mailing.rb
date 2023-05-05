class Mailings::Mailing < ApplicationRecord
  # scheduling
  # include Scheduling::ScheduledAction

  # relationships
  belongs_to :list, optional: true
  belongs_to :campaign, optional: true
  belongs_to :parent, class_name: 'Mailings::Mailing', foreign_key: "parent_mailing_id", optional: true
  belongs_to :cloned, class_name: 'Mailings::Mailing', foreign_key: "cloned_mailing_id", optional: true
  belongs_to :search
  # has_one :source
  # has_many :member_actions, through: :source
  has_many :donations, through: :member_actions
  # has_many :links, -> { order 'id ASC' }, class_name: 'Mailings::MailingLink'
  has_many :tests, -> { order 'id ASC' }, class_name: 'Mailings::MailingTest'
  has_many :test_cases, through: :tests
  has_many :mailing_variations, class_name: 'Mailings::MailingVariation'
  # has_many :mailing_logs, class_name: 'Mailer::MailingLog'
  has_many :member_mailings
  has_many :members, through: :member_mailings
  has_and_belongs_to_many :actions
  has_many :opens, through: :member_mailings
  has_many :clicks, through: :member_mailings
  has_many :unsubscribes, class_name: 'MemberSubscription', foreign_key: 'unsubscribe_mailing_id'

  accepts_nested_attributes_for :tests

  validates_uniqueness_of :external_id, allow_blank: true, allow_nil: true
  validates_presence_of :recurring_schedule, :recurring_at, :recurring_max_recipients_per_send, :search_id, if: :recurring

  attr_accessor :updating_system # Allow us to specify to the Mailing whether the update is coming via the API or frontend.

  API_FIELDS = %w(id name subject body_html body_plain updated_at member_count mailing_template_id list_id started_send_at prepared_send_at finished_sending_at total_opens total_clicks from_name from_email total_spam_reports total_bounces total_unsubscribes scheduled_for campaign_id).freeze
  API_UPDATE_FIELDS = %w(name subject body_html body_plain mailing_template_id list_id from_name from_email scheduled_for is_controlled_externally).freeze

  def as_cache_key
    { id: id }
  end

  def self.name_contains(search)
    where('name ILIKE ?', "%#{sanitize_sql_like(search)}%").order(sanitize_sql_for_order(["#{Settings.databases.extensions_schemas.core}.similarity(name, ?)", search]))
  end

  # remove mailing and all dependencies
  def remove
    return false unless started_send_at.nil?

    # remove associations
    tests.each(&:remove)
    mailing_variations.destroy_all

    delete
  end

  # clone mailing with tests
  def clone(recurring = false)
    clone = deep_clone include: [{ tests: :test_cases }],
                       only: %i[
                         name
                         subject
                         body_html
                         mailing_template_id
                         from_name
                         from_email
                         reply_to
                         external_slug
                       ]

    if recurring
      clone.name = "#{name} - #{DateTime.now.strftime('%d/%m/%Y')}"
      clone.parent_mailing_id = id
    else
      clone.name = "#{name} [CLONE]"
      clone.cloned_mailing_id = id
    end

    clone.save!

    clone.id
  end

  # create a recurring copy
  def create_recurring_copy
    clone(true)
  end

  # gets variation ids
  def variation_ids
    mailing_variations.pluck(:id)
  end

  def update_counts
    don_model = Donations::Donation.arel_table
    donate_amount, donate_count = Donations::Donation
                                  .joins(member_action: :source)
                                  .where(member_actions: { sources: { mailing_id: id } }, regular_donation_id: nil)
                                  .pick(don_model[:amount].sum, don_model[:id].count)

    reg_don_model = Donations::RegularDonation.arel_table
    reg_donate_amount, reg_donate_count = Donations::RegularDonation
                                          .joins(member_action: :source)
                                          .where(member_actions: { sources: { mailing_id: id } })
                                          .pick(reg_don_model[:current_amount].sum, reg_don_model[:id].count)

    update!(
      total_opens: MemberMailing.where(mailing_id: id).where('first_opened IS NOT NULL').count,
      total_clicks: MemberMailing.where(mailing_id: id).where('first_clicked IS NOT NULL').count,
      total_actions: MemberAction.joins(:source).where(sources: { mailing_id: id }).distinct.count(:member_id),
      total_unsubscribes: MemberSubscription.where(unsubscribe_mailing_id: id).count,
      total_donate_amount: donate_amount || 0,
      total_donate_count: donate_count,
      total_reg_donate_amount: reg_donate_amount || 0,
      total_reg_donate_count: reg_donate_count
    )
  end
end
