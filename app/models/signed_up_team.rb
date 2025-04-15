class SignedUpTeam < ApplicationRecord
  belongs_to :sign_up_topic
  belongs_to :team

  def self.find_team_participants(assignment_id, ip_address = nil)
    @participants = SignedUpTeam.joins('INNER JOIN sign_up_topics ON signed_up_teams.sign_up_topic_id = sign_up_topics.id')
                                .select('signed_up_teams.id as id, sign_up_topics.id as topic_id, sign_up_topics.topic_name as name,
                                  sign_up_topics.topic_name as team_name_placeholder, sign_up_topics.topic_name as user_name_placeholder,
                                  signed_up_teams.is_waitlisted as is_waitlisted, signed_up_teams.team_id as team_id')
                                .where('sign_up_topics.assignment_id = ?', assignment_id)
  
    @participants.each_with_index do |participant, i|
      participant_names = User.joins('INNER JOIN teams_users ON users.id = teams_users.user_id')
                              .joins('INNER JOIN teams ON teams.id = teams_users.team_id')
                              .select('users.*, teams.name as team_name')
                              .where('teams.id = ?', participant.team_id)
  
      team_name_added = false
      names = '(missing team)'
  
      participant_names.each do |participant_name|
        user_name = participant_name.name.to_s
        if team_name_added
          names += user_name + ' '
          participant.user_name_placeholder += user_name + ' '
        else
          names = '[' + participant_name.team_name.to_s + '] ' + user_name + ' '
          participant.team_name_placeholder = participant_name.team_name
          participant.user_name_placeholder = user_name + ' '
          team_name_added = true
        end
      end
  
      @participants[i].name = names
    end
  
    @participants
  end  
end
