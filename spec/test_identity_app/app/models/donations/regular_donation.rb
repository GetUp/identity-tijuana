class Donations::RegularDonation < ApplicationRecord
  belongs_to :member
  belongs_to :member_action, optional: true
  has_many :donations, class_name: 'Donations::Donation'
  validates_presence_of :member_id

  scope :active, -> { where("ended_at IS NULL OR ended_at > ?", Time.zone.now) }
  scope :inactive, -> { where("ended_at <= ?", Time.zone.now) }

  def self.upsert!(attrs)
    rd = Donations::RegularDonation.find_or_initialize_by(attrs.slice(:medium, :external_id))

    if rd.persisted? && attrs[:member_id] != rd.member_id
      raise ArgumentError.new("member_id provided (#{attrs[:member_id]}) does not match existing regular donation record (#{rd.member_id})")
    end

    if rd.new_record?
      rd.update!(attrs)
    elsif attrs[:updated_at].present? && attrs[:updated_at] > rd.updated_at
      rd.update!(attrs.except(:started_at, :initial_amount))
    elsif attrs[:member_action_id].present? && rd.member_action_id.blank?
      rd.update!(attrs.slice(:member_action_id))
    end

    return rd
  end

  def update_amount_last_changed_at
    if updated_at_changed?
      self.amount_last_changed_at = updated_at
    else
      self.amount_last_changed_at = DateTime.now
    end
  end
  before_save :update_amount_last_changed_at, if: :current_amount_changed?

  def update_initial_amount
    self.initial_amount = current_amount if initial_amount.nil?
  end
  before_save :update_initial_amount
end
