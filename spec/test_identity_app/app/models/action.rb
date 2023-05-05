class Action < ApplicationRecord
  belongs_to :campaign, optional: true
  delegate :issue, to: :campaign
  # has_many :member_actions
  has_many :members, through: :member_actions
  # has_many :action_keys
  # has_many :questions, through: :action_keys
  has_and_belongs_to_many :mailings, class_name: "Mailings::Mailing"

  validates_uniqueness_of :external_id, scope: [:technical_type, :language], allow_blank: true, allow_nil: true
end
