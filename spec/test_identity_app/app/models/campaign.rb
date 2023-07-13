class Campaign < ApplicationRecord
  has_many :actions
  has_many :mailings
  belongs_to :issue, optional: true
  belongs_to :author, class_name: 'Member', optional: true
end
