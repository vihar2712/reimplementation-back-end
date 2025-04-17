class Participant < ApplicationRecord
  # Associations
  belongs_to :user
  belongs_to :assignment, foreign_key: 'assignment_id', optional: true, inverse_of: false
  belongs_to :course, foreign_key: 'course_id', optional: true, inverse_of: false
  has_many   :join_team_requests, dependent: :destroy
  belongs_to :team, optional: true

  has_many :response_maps,
           class_name: 'ResponseMap',
           foreign_key: 'reviewer_id',
           dependent: :destroy,
           inverse_of: false

  # delegate :course, to: :assignment, allow_nil: true

  # Validations
  validates :user_id, presence: true
  # Validation: require either assignment_id or course_id
  validate :assignment_or_course_presence

  # Methods
  def name
    user.full_name
  end

  def responses
    response_maps.includes(:response).map(&:response)
  end

  def username
    user.name
  end

  def handle(_ip_address = nil)
    read_attribute(:handle)
  end

  def delete(force = nil)
    maps = ResponseMap.where('reviewee_id = ? or reviewer_id = ?', id, id)

    raise 'Associations exist for this participant.' unless force || (maps.blank? && team.nil?)

    force_delete(maps)
  end

  def force_delete(maps)
    maps && maps.each(&:destroy)
    if team && (team.teams_users.length == 1)
      team.delete
    elsif team
      team.teams_users.each { |teams_user| teams_user.destroy if teams_user.user_id == id }
    end
    destroy
  end

  def authorization
    role = 'participant'
    role = 'mentor'    if can_mentor
    role = 'reader'    if !can_submit && can_review   && can_take_quiz
    role = 'submitter' if  can_submit && !can_review  && !can_take_quiz
    role = 'reviewer'  if !can_submit && can_review   && !can_take_quiz
    role
  end

  def self.export(csv, parent_id, options)
    where(assignment_id: parent_id).find_each do |part|
      tcsv = []
      user = part.user
      tcsv.push(user.name, user.full_name, user.email) if options['personal_details'] == 'true'
      tcsv.push(user.role.name) if options['role'] == 'true'
      tcsv.push(user.institution.name) if options['parent'] == 'true'
      tcsv.push(user.email_on_submission, user.email_on_review, user.email_on_review_of_review) if options['email_options'] == 'true'
      tcsv.push(part.handle) if options['handle'] == 'true'
      csv << tcsv
    end
  end

  private

  def assignment_or_course_presence
    if assignment.blank? && course.blank?
      errors.add(:base, "Either assignment or course must be present")
    elsif assignment.present? && course.present?
      errors.add(:base, "A Participant cannot be both an AssignmentParticipant and a CourseParticipant.")
    end
  end
end
