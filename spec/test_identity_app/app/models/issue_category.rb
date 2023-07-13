# == Schema Information
#
# Table name: issue_categories
#
#  id         :integer          not null, primary key
#  name       :text
#  created_at :datetime
#  updated_at :datetime
#

class IssueCategory < ApplicationRecord
  has_and_belongs_to_many :issues

  validates_uniqueness_of :name
end
