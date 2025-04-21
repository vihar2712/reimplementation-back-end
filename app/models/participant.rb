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
  validate :parent_absent?

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

  def task_role
    task = 'participant'
    task = 'mentor'    if can_mentor
    task = 'reader'    if !can_submit && can_review   && can_take_quiz
    task = 'submitter' if  can_submit && !can_review  && !can_take_quiz
    task = 'reviewer'  if !can_submit && can_review   && !can_take_quiz
    task
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

  def self.export_options
    {
      'personal_details' => {
        'display' => 'Include personal details',
        'fields' => ['name', 'full name', 'email']
      },
      'role' => {
        'display' => 'Include role',
        'fields' => ['role']
      },
      'parent' => {
        'display' => 'Include parent information',
        'fields' => ['parent']
      },
      'email_options' => {
        'display' => 'Include email preferences',
        'fields' => ['email on submission', 'email on review', 'email on metareview']
      },
      'handle' => {
        'display' => 'Include handle',
        'fields' => ['handle']
      }
    }
  end


  private

  def parent_absent?
    if assignment.blank? && course.blank?
      errors.add(:base, "Either assignment or course must be present")
    elsif assignment.present? && course.present?
      errors.add(:base, "A Participant cannot be both an AssignmentParticipant and a CourseParticipant.")
    end
  end
end
