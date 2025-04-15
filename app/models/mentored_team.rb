class MentoredTeam < AssignmentTeam
  # Adds a member to the team and assigns a mentor (if applicable)
  def add_member(participant)
    can_add_member = super(participant.user)
    if can_add_member
      assign_mentor(parent_id, id)
    end
    can_add_member
  end

  # Imports team members from the provided row hash and assigns mentors if necessary
  def import_team_members(row_hash)
    row_hash[:teammembers].each do |teammate|
      if teammate.to_s.strip.empty?
        next
      end
      user = User.find_by(name: teammate.to_s)
      if user.nil?
        raise ImportError, "The user '#{teammate}' was not found. <a href='/users/new'>Create</a> this user?"
      else
        unless TeamsUser.find_by(team_id: id, user_id: user.id)
          participant = AssignmentParticipant.find_by(user_id: user.id, assignment_id: parent_id)
          add_member(participant) if participant
        end
      end
    end
  end

  # Overrides size to exclude the mentor
  def size
    [super - 1, 0].max # Ensures the size never goes negative
  end

  private

  # Determines if a mentor should be auto-assigned to the team,
  # and if so, selects and assigns the mentor, then notifies users.
  def assign_mentor(assignment_id, team_id)
    assignment = Assignment.find(assignment_id)
    team = Team.find(team_id)

    # return if assignments can't accept mentors
    return unless assignment.auto_assign_mentor

    # return if the assignment or team already have a topic
    return if assignment.topics? || !team.topic_id.nil?

    # return if the team size hasn't reached > 50% of capacity
    return if team.size * 2 <= assignment.max_team_size

    # return if there's already a mentor in place
    return if team.participants.any?(&:can_mentor)

    mentor = select_mentor(assignment_id)

    # Add the mentor using team model class.
    team_member_added = mentor.nil? ? false : team.add_member(mentor)
    return unless team_member_added

    notify_team_of_mentor_assignment(mentor, team)
    notify_mentor_of_assignment(mentor, team)
  end

  # Select a mentor using the following algorithm
  #
  # 1) Find all assignment participants for the
  #    assignment with id [assignment_id] whose
  #    duty is the same as [Particpant#DUTY_MENTOR].
  # 2) Count the number of teams those participants
  #    are a part of, acting as a proxy for the
  #    number of teams they mentor.
  # 3) Return the mentor with the fewest number of
  #    teams they're currently mentoring.
  #
  # This method's runtime is O(n lg n) due to the call to
  # Hash#sort_by. This assertion assumes that the
  # database management system is capable of fetching the
  # required rows at least as quickly.
  #
  # Implementation detail: Any tie between the top 2
  # mentors is decided by the Hash#sort_by algorithm.
  #
  # @return The id of the mentor with the fewest teams
  #   they are assigned to. Returns `nil` if there are
  #   no participants with mentor duty for [assignment_id].
  def select_mentor(assignment_id)
    mentor_user_id, = zip_mentors_with_team_count(assignment_id).first
    User.where(id: mentor_user_id).first
  end

  # Produces a hash mapping mentor's user_ids to the aggregated
  # number of teams they're part of, which acts as a proxy for
  # the number of teams they're mentoring.
  def zip_mentors_with_team_count(assignment_id)
    mentor_ids = mentors_for_assignment(assignment_id).pluck(:user_id)
    return [] if mentor_ids.empty?
    team_counts = {}
    mentor_ids.each { |id| team_counts[id] = 0 }
    #E2351 removed (:team_id) after .count to fix balancing algorithm
    team_counts.update(TeamsUser
    .joins(:team)
    .where(teams: { parent_id: assignment_id })
    .where(user_id: mentor_ids)
    .group(:user_id)
    .count)
    team_counts.sort_by { |_, v| v }
  end

  # Select all the participants who's duty in the participant
  # table is [DUTY_MENTOR], and who are a participant of
  # [assignment_id].
  #
  # @see participant.rb for the value of DUTY_MENTOR
  def mentors_for_assignment(assignment_id)
    Participant.where(parent_id: assignment_id, can_mentor: true)
  end

  # Sends an email notification to all team members informing them that a mentor has been assigned.
  # The message includes the mentor’s name and email, the assignment name, and a list of current members.
  def notify_team_of_mentor_assignment(mentor, team)
    members = team.users
    emails = members.map(&:email)
    members_info = members.map { |mem| "#{mem.fullname} - #{mem.email}" }
    mentor_info = "#{mentor.fullname} (#{mentor.email})"
    message = "#{mentor_info} has been assigned as your mentor for assignment #{Assignment.find(team.parent_id).name} <br>Current members:<br> #{members_info.join('<br>')}"

    Mailer.delayed_message(bcc: emails,
                           subject: '[Expertiza]: New Mentor Assignment',
                           body: message).deliver_now
  end

  # Sends an email notification to the assigned mentor with details about their team.
  # Includes the assignment name and a list of current team members.
  def notify_mentor_of_assignment(mentor, team)
    members_info = team.users.map { |mem| "#{mem.fullname} - #{mem.email}" }.join('<br>')
    assignment_name = Assignment.find(team.parent_id).name
    mentor_message = "You have been assigned as a mentor for the team working on assignment: #{assignment_name}. <br>Current team members:<br> #{members_info}"
  
    Mailer.delayed_message(
        bcc: [mentor.email],
        subject: '[Expertiza]: You have been assigned as a Mentor',
        body: mentor_message
      ).deliver_now

  end
end
