class Issue < ApplicationRecord
  has_many :campaigns
  has_and_belongs_to_many :issue_categories

  validates_uniqueness_of :name
end
