class AssignmentTeam < Team
  belongs_to :assignment, class_name: 'Assignment', foreign_key: 'parent_id'
  has_many :review_mappings, class_name: 'ReviewResponseMap', foreign_key: 'reviewee_id'
  has_many :review_response_maps, foreign_key: 'reviewee_id'
  has_many :responses, through: :review_response_maps, foreign_key: 'map_id'

  def current_user_id
    return @current_user.id if @current_user && participants.map(&:user).include?(@current_user)

    nil
  end

  def first_user_id
    participants.first&.user_id
  end


  def store_current_user(current_user)
    @current_user = current_user
  end

  def review_map_type
    'ReviewResponseMap'
  end

  def assign_reviewer(reviewer)
    assignment = Assignment.find(parent_id)
    raise 'The assignment cannot be found.' if assignment.nil?

    ReviewResponseMap.create(reviewee_id: id, reviewer_id: reviewer.get_reviewer.id, reviewed_object_id: assignment.id, team_reviewing_enabled: assignment.team_reviewing_enabled)
  end

  def reviewer
    self
  end

  def reviewed_by?(reviewer)
    ReviewResponseMap.where('reviewee_id = ? && reviewer_id = ? && reviewed_object_id = ?', id, reviewer.get_reviewer.id, assignment.id).count > 0
  end

  def topic_id
    SignedUpTeam.find_by(team_id: id, is_waitlisted: 0)&.sign_up_topic_id
  end

  def has_submissions?
    submitted_files.any? || submitted_hyperlinks.present?
  end

  def participants
    TeamsParticipant.where(team_id: id).includes(:participant).map(&:participant).select { |p| p.assignment_id == assignment_id }
  end
  alias get_participants participants

  def delete
    if self[:type] == 'AssignmentTeam'
      sign_up = SignedUpTeam.find_team_participants(parent_id.to_s).select { |p| p.team_id == id }
      sign_up.each(&:destroy)
    end
    super
  end

  def destroy
    review_response_maps.each(&:destroy)
    super
  end

  def submitted_files(path = self.path)
    files = []
    files = files(path) if directory_num
    files
  end

  def self.import(row, assignment_id, options)
    raise ImportError, "The assignment with the id \"#{assignment_id}\" was not found. <a href='/assignment/new'>Create</a> this assignment?" unless Assignment.find_by(id: assignment_id)
    Team.import(row, assignment_id, options, AssignmentTeam)
  end

  def self.export(csv, parent_id, options)
    Team.export(csv, parent_id, options, AssignmentTeam)
  end

  def copy(new_team)
    members = TeamsParticipant.where(team_id: id)
    members.each do |member|
      old_participant = member.participant

      new_participant =
        if new_team.is_a?(AssignmentTeam)
          AssignmentParticipant.find_or_create_by!(
            user_id: old_participant.user_id,
            assignment_id: new_team.assignment_id
          ) do |p|
            p.handle = old_participant.handle
          end
        else
          nil
        end

      TeamsParticipant.create!(
        team_id: new_team.id,
        participant: new_participant || member.participant
      )

      parent = Assignment.find_by(id: parent_id) || Course.find_by(id: new_team.parent_id)
      TeamUserNode.create!(parent_id: parent.id, node_object_id: new_team.id)
    end
  end


  def copy_assignment_to_course(course_id)
    new_team = CourseTeam.create_team_and_node(course_id)
    new_team.name = name
    new_team.save
    copy(new_team)
  end

  def participant_class
    AssignmentParticipant
  end

  def hyperlinks
    submitted_hyperlinks.blank? ? [] : YAML.safe_load(submitted_hyperlinks)
  end

  def submit_hyperlink(hyperlink)
    hyperlink.strip!
    raise 'The hyperlink cannot be empty!' if hyperlink.empty?
    hyperlink = 'http://' + hyperlink unless hyperlink.start_with?('http://', 'https://')
    response_code = Net::HTTP.get_response(URI(hyperlink))
    raise "HTTP status code: #{response_code}" if response_code =~ /[45][0-9]{2}/

    hyperlinks = self.hyperlinks
    hyperlinks << hyperlink
    self.submitted_hyperlinks = YAML.dump(hyperlinks)
    save
  end

  def remove_hyperlink(hyperlink_to_delete)
    hyperlinks = self.hyperlinks
    hyperlinks.delete(hyperlink_to_delete)
    self.submitted_hyperlinks = YAML.dump(hyperlinks)
    save
  end

  def files(directory)
    return [] unless File.directory?(directory)

    (Dir.entries(directory) - ['.', '..']).flat_map do |entry|
      path = File.join(directory, entry)
      File.directory?(path) ? files(path) : [path]
    end
  end

  def self.team(participant)
    return nil if participant.nil?

    teams_users = TeamsParticipant.where(participant_id: participant.id)
    return nil if teams_users.empty?

    teams_users.each do |teams_user|
      next if teams_user.team_id.nil?
      team = Team.find_by(id: teams_user.team_id)
      return team if team&.parent_id == participant.assignment_id
    end

    nil
  end

  def self.export_fields(options)
    fields = ['Team Name']
    fields << 'Team members' if options[:team_name] == 'false'
    fields << 'Assignment Name'
    fields
  end

  def self.remove_team_by_id(id)
    old_team = AssignmentTeam.find(id)
    old_team.destroy unless old_team.nil?
  end

  def path
    File.join(assignment.directory_path, directory_num.to_s)
  end

  def set_team_directory_num
    return if directory_num && (directory_num >= 0)
    max_num = AssignmentTeam.where(parent_id: parent_id).order('directory_num desc').first&.directory_num
    dir_num = max_num ? max_num + 1 : 0
    update(directory_num: dir_num)
  end

  def has_been_reviewed?
    ResponseMap.where(reviewee_id: id, reviewed_object_id: parent_id).any?
  end

  def most_recent_submission
    assignment = Assignment.find(parent_id)
    SubmissionRecord.where(team_id: id, assignment_id: assignment.id).order(updated_at: :desc).first
  end

  def get_logged_in_reviewer_id(current_user_id)
    participants.each do |participant|
      return participant.id if participant.user.id == current_user_id
    end
    nil
  end

  def current_user_is_reviewer?(current_user_id)
    get_logged_in_reviewer_id(current_user_id) != nil
  end

  def assign_team_to_topic(signup_topic)
    SignedUpTeam.create(sign_up_topic_id: signup_topic.id, team_id: id, is_waitlisted: 0)
    team_node = TeamNode.create(parent_id: signup_topic.assignment_id, node_object_id: id)

    TeamsParticipant.where(team_id: id).each do |team_user|
      TeamUserNode.create(parent_id: team_node.id, node_object_id: team_user.id)
    end
  end
end
