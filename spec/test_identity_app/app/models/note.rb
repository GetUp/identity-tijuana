# == Schema Information
#
# Table name: notes
#
#  id           :integer          not null, primary key
#  note_type_id :integer
#  user_id      :integer
#  member_id    :integer
#  text         :text
#  created_at   :datetime
#  updated_at   :datetime
#

class Note < ApplicationRecord
  belongs_to :member
  belongs_to :note_type
  belongs_to :user, class_name: 'Member'

  validates_presence_of :member, :note_type
end
