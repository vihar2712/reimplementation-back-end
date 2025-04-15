require 'rails_helper'

RSpec.describe SignedUpTeam, type: :model do
  before do
    $redis = double('Redis', get: '')
  end

  describe '#find_team_participants' do
    let(:topic) { SignUpTopic.create!(topic_name: 'Topic 1', assignment_id: assignment.id) }
    let(:team) { Team.create!(name: 'Team A', parent_id: assignment.id) }
    let(:student_role) { Role.create!(name: 'Student') }
    let(:user) do
      User.create!(
        name: 'student1',
        full_name: 'Student One',
        email: 'student1@example.com',
        password: 'password',
        role: student_role
      )
    end
    let(:instructor) do
      User.create!(
        name: 'Instructor',
        full_name: 'Dr. Smith',
        email: 'instructor@example.com',
        password: 'password',
        role: Role.find_or_create_by!(name: 'Instructor')
      )
    end
    let(:assignment) do
      Assignment.create!(
        title: 'Test Assignment',
        directory_path: 'test_path',
        max_team_size: 2,
        instructor_id: instructor.id
      )
    end

    before do
      @signed_up_team = SignedUpTeam.create!(sign_up_topic: topic, team: team, is_waitlisted: false)
      TeamsUser.create!(team: team, user: user)
    end

    it 'returns participants with correct team and user names filled in' do
      participants = SignedUpTeam.find_team_participants(assignment.id)

      expect(participants.length).to eq(1)
      participant = participants.first

      expect(participant.team_id).to eq(team.id)
      expect(participant.topic_id).to eq(topic.id)
      expect(participant.name).to include(team.name)
      expect(participant.name).to include(user.name)
      expect(participant.team_name_placeholder).to eq(team.name)
      expect(participant.user_name_placeholder).to include(user.name)
    end

    it 'returns an empty array if there are no matching participants' do
      SignedUpTeam.destroy_all
      result = SignedUpTeam.find_team_participants(assignment.id)
      expect(result).to be_empty
    end
  end
end
