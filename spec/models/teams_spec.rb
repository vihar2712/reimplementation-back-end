require 'rails_helper'

RSpec.describe Team, type: :model do
  let(:role) { Role.create!(name: 'Instructor') }
  let(:instructor) do
    User.create!(
      name: 'instructor1',
      full_name: 'Instructor One',
      email: 'instructor1@example.com',
      password: 'password',
      role: role
    )
  end
  let(:assignment) { Assignment.create!(title: 'Test Assignment', instructor: instructor) }
  let(:user_parent) do
    User.create!(
      name: 'parent_user',
      full_name: 'Parent User',
      email: 'parent@example.com',
      password: 'password',
      role: role
    )
  end

  before do
    $redis = double("Redis", get: '')
  end

  describe '#parent_entity_type' do
    it 'returns "Assignment" for an AssignmentTeam' do
      team = AssignmentTeam.new
      expect(team.parent_entity_type).to eq('Assignment')
    end
  end

  describe '#find_parent_entity' do
    it 'returns the parent Assignment object for an AssignmentTeam' do
      assignment = Assignment.create!(title: 'Parent Assignment', instructor: instructor)
      result = AssignmentTeam.find_parent_entity(assignment.id)
      expect(result).to eq(assignment)
    end
  end

  describe '#participants' do
    it 'returns participants for each user in the team' do
      team = Team.create!(name: 'PartTeam', parent_id: user_parent.id, assignment: assignment)

      user1 = User.create!(
        name: 'userA', full_name: 'User A', email: 'usera@example.com',
        password: 'password', role: role, parent: user_parent
      )
      user2 = User.create!(
        name: 'userB', full_name: 'User B', email: 'userb@example.com',
        password: 'password', role: role, parent: user_parent
      )

      TeamsUser.create!(team: team, user: user1)
      TeamsUser.create!(team: team, user: user2)

      participant1 = AssignmentParticipant.create!(user: user1, assignment: assignment, handle: 'handle1')
      participant2 = AssignmentParticipant.create!(user: user2, assignment: assignment, handle: 'handle2')

      expect(team.participants.map(&:id)).to contain_exactly(participant1.id, participant2.id)
    end
  end

  describe '#copy_content' do
    it 'calls copy on each element with destination id' do
      source = [double('Element1'), double('Element2')]
      destination = double('Destination', id: 42)
  
      source.each do |el|
        expect(el).to receive(:copy).with(42)
      end
  
      Team.copy_content(source, destination)
    end
  end

  describe '#delete' do
    it 'deletes the team and its team node without touching bids' do
      team = Team.create!(name: 'TeamToDelete', parent_id: assignment.id, assignment: assignment)
      TeamsUser.create!(team: team, user: instructor)

      allow(team).to receive(:destroy).and_return(true)

      mock_node = double('TeamNode', destroy: true)
      allow(TeamNode).to receive(:find_by).with(node_object_id: team.id).and_return(mock_node)

      expect(team).to receive(:destroy)
      team.delete
    end
  end

  describe '#node_type' do
    it 'returns "TeamNode"' do
      team = Team.new
      expect(team.node_type).to eq('TeamNode')
    end
  end

  describe '#member_names' do
    it 'returns full names of associated users' do
      team = Team.create!(name: 'TeamTest', parent_id: 1, assignment: assignment)
      user1 = User.create!(name: 'user1', full_name: 'Full Name 1', email: 'user1@example.com', password: 'password', role: role)
      user2 = User.create!(name: 'user2', full_name: 'Full Name 2', email: 'user2@example.com', password: 'password', role: role)
      TeamsUser.create!(team: team, user: user1)
      TeamsUser.create!(team: team, user: user2)

      expect(team.member_names).to contain_exactly('Full Name 1', 'Full Name 2')
    end
  end

  describe '#has_as_member?' do
    it 'returns true if user is a member' do
      team = Team.create!(name: 'TeamTest', parent_id: 1, assignment: assignment)
      user = User.create!(name: 'user3', full_name: 'Full Name', email: 'user3@example.com', password: 'password', role: role)
      TeamsUser.create!(team: team, user: user)

      expect(team.has_as_member?(user)).to be true
    end

    it 'returns false if user is not a member' do
      team = Team.create!(name: 'TeamTest', parent_id: 1, assignment: assignment)
      user = User.create!(name: 'user4', full_name: 'Full Name', email: 'user4@example.com', password: 'password', role: role)

      expect(team.has_as_member?(user)).to be false
    end
  end

  describe '#full?' do
    it 'returns false for course team (no max size limit)' do
      team = Team.create!(name: 'TeamTest', parent_id: nil, assignment: assignment)
      expect(team.full?).to be false
    end

    it 'returns false if team size is below max' do
      assignment.update!(max_team_size: 2)
      team = Team.create!(name: 'TeamTest', parent_id: assignment.id, assignment: assignment)
      user = User.create!(name: 'user7', full_name: 'Full Name', email: 'user7@example.com', password: 'password', role: role)
      TeamsUser.create!(team: team, user: user)

      expect(team.full?).to be false
    end

    it 'returns true if team size equals or exceeds max' do
      assignment.update!(max_team_size: 1)
      team = Team.create!(name: 'TeamTest', parent_id: assignment.id, assignment: assignment)
      user = User.create!(name: 'user8', full_name: 'Full Name', email: 'user8@example.com', password: 'password', role: role)
      TeamsUser.create!(team: team, user: user)

      expect(team.full?).to be true
    end
  end

  describe '#add_member' do
    let(:team) { Team.create!(name: 'TeamAdd', parent_id: assignment.id, assignment: assignment) }
    let(:user) { User.create!(name: 'new_user', full_name: 'New Member', email: 'new@example.com', password: 'password', role: role) }

    it 'adds a user to the team successfully' do
      assignment.update!(max_team_size: 5) 
      allow(TeamNode).to receive(:find_by).and_return(double('TeamNode', id: 1))
      allow(TeamUserNode).to receive(:create)
      allow(CourseParticipant).to receive(:find_by).and_return(nil)
      allow(CourseParticipant).to receive(:create)

      result = team.add_member(user)
      expect(result).to be true
    end

    it 'raises an error if the user is already a member' do
      TeamsUser.create!(team: team, user: user)
      expect { team.add_member(user) }.to raise_error(RuntimeError)
    end

    it 'returns false if the team is full' do
      assignment.update!(max_team_size: 0)
      expect(team.add_member(user)).to be false
    end
  end

  describe '#add_participant' do
    let(:user) do
      User.create!(
        name: 'participant_user',
        full_name: 'Participant',
        email: 'participant@example.com',
        password: 'password',
        role: role,
        master_permission_granted: true
      )
    end

    let(:team) do
      AssignmentTeam.create!(
        name: 'TeamAddParticipant',
        parent_id: assignment.id,
        assignment_id: assignment.id,
        assignment: assignment
      )
    end

    it 'creates a participant if one does not already exist' do
      expect {
        team.add_participant(user)
      }.to change { AssignmentParticipant.count }.by(1)
  
      participant = AssignmentParticipant.last
      expect(participant.user_id).to eq(user.id)
      expect(participant.assignment_id).to eq(team.parent_id)
    end

    it 'returns nil if participant already exists' do
      user = User.create!(name: 'existing_participant', full_name: 'Existing', email: 'exist@example.com', password: 'password', role: role)
      AssignmentParticipant.create!(user: user, assignment: assignment, handle: 'exist_handle')

      expect(team.add_participant(user)).to be_nil
    end
  end

  describe '#size' do
    it 'returns the number of users in the team' do
      team = Team.create!(name: 'TeamTest', parent_id: 1, assignment: assignment)
      user1 = User.create!(name: 'user5', full_name: 'Full Name 1', email: 'user5@example.com', password: 'password', role: role)
      user2 = User.create!(name: 'user6', full_name: 'Full Name 2', email: 'user6@example.com', password: 'password', role: role)
      TeamsUser.create!(team: team, user: user1)
      TeamsUser.create!(team: team, user: user2)

      expect(team.size).to eq(2)
    end
  end

  describe '#create_random_teams' do
    let(:assignment_with_teams) { Assignment.create!(title: 'Auto Team Assignment', instructor: instructor, max_team_size: 2) }

    it 'creates teams with minimum team size using available users' do
      4.times do |i|
        user = User.create!(
          name: "user_random_#{i}",
          full_name: "Random User #{i}",
          email: "random#{i}@example.com",
          password: 'password',
          role: role
        )
        AssignmentParticipant.create!(
          user: user,
          assignment_id: assignment_with_teams.id,
          handle: "handle_#{i}"
        )
      end

      allow(TeamNode).to receive(:create)
      allow_any_instance_of(Team).to receive(:add_member).and_return(true)

      Team.create_random_teams(assignment_with_teams, 'Assignment', 2)

      created_teams = Team.where(parent_id: assignment_with_teams.id)
      expect(created_teams.count).to be > 0
    end
  end

  describe '#team_from_users' do
    it 'creates new teams from a list of users' do
      assignment.update!(max_team_size: 2)
  
      users = 4.times.map do |i|
        User.create!(
          name: "tfu_user#{i}",
          full_name: "TFU User #{i}",
          email: "tfu#{i}@example.com",
          password: 'password',
          role: role
        )
      end
  
      allow(TeamNode).to receive(:create)
      allow_any_instance_of(Team).to receive(:add_member).and_return(true)
  
      Team.team_from_users(2, assignment, 'Assignment', users)
  
      expect(Team.where(parent_id: assignment.id).count).to eq(2)
    end
  end  

  describe '#generate_team_name' do
    it 'generates a team name with the default prefix' do
      Team.create!(name: 'Team_1', parent_id: assignment.id, assignment: assignment)
      name = Team.generate_team_name
      expect(name).to match(/Team_\d+/)
    end
  end

  describe '#name' do
    let(:team) do
      AssignmentTeam.create!(
        name: 'Visible Team',
        parent_id: assignment.id,
        assignment_id: assignment.id
      )
    end

    before do
      allow(User).to receive(:anonymized_view?).with(nil).and_return(false)
    end

    context 'when anonymized view is enabled' do
      it 'returns anonymized team name' do
        allow(User).to receive(:anonymized_view?).with('127.0.0.1').and_return(true)
        expect(team.name('127.0.0.1')).to eq("Anonymized_Team_#{team.id}")
      end
    end

    context 'when anonymized view is disabled' do
      it 'returns the actual team name' do
        allow(User).to receive(:anonymized_view?).with('127.0.0.1').and_return(false)
        expect(team.name('127.0.0.1')).to eq('Visible Team')
      end
    end
  end

  describe '#import_team_members' do
    let(:team) { AssignmentTeam.create!(name: 'TeamImportMembers', parent_id: assignment.id, assignment_id: assignment.id) }

    it 'adds each listed user to the team if found and not already added' do
      user1 = User.create!(name: 'member_one', full_name: 'Member One', email: 'one@example.com', password: 'password', role: role)
      user2 = User.create!(name: 'member_two', full_name: 'Member Two', email: 'two@example.com', password: 'password', role: role)

      assignment.update!(max_team_size: 10)

      allow(TeamNode).to receive(:find_by).and_return(TeamNode.create!(parent_id: assignment.id, node_object_id: team.id))
      allow(TeamUserNode).to receive(:create)
      allow(CourseParticipant).to receive(:find_by).and_return(nil)
      allow(CourseParticipant).to receive(:create)

      row_hash = { teammembers: ['member_one', 'member_two'] }

      expect {
        team.import_team_members(row_hash)
      }.to change { team.teams_users.count }.by(2)

      expect(team.users.reload).to include(user1, user2)
    end
  end

  describe '#import' do
    let(:assignment_team_class) { AssignmentTeam }
    let(:assignment_id) { assignment.id }
  
    it 'creates a team and imports members' do
      user = User.create!(name: 'import_user', full_name: 'Import User', email: 'import@example.com', password: 'password', role: role)
      assignment.update!(max_team_size: 5)
  
      row = { teamname: 'Import Team', teammembers: ['import_user'] }
      options = { has_teamname: 'true_first', handle_dups: 'insert' }
  
      fake_team = AssignmentTeam.create!(name: 'Import Team', parent_id: assignment.id, assignment_id: assignment.id)
  
      allow(assignment_team_class).to receive(:create_team_and_node).and_return(fake_team)
      allow(TeamNode).to receive(:find_by).and_return(double('TeamNode', id: 1))
      allow(TeamUserNode).to receive(:create)
      allow(CourseParticipant).to receive(:find_by).and_return(nil)
      allow(CourseParticipant).to receive(:create)
  
      expect {
        Team.import(row, assignment_id, options, assignment_team_class)
      }.not_to raise_error
  
      expect(fake_team.users).to include(user)
    end
  end

  describe '#handle_duplicate' do
    let(:existing_team) { Team.create!(name: 'Existing Team', parent_id: assignment.id, assignment: assignment) }
  
    it 'returns the name if no duplicate exists' do
      result = Team.handle_duplicate(nil, 'Team Alpha', assignment.id, 'ignore', AssignmentTeam)
      expect(result).to eq('Team Alpha')
    end
  
    it 'returns nil if handle_dups is ignore' do
      result = Team.handle_duplicate(existing_team, 'Existing Team', assignment.id, 'ignore', AssignmentTeam)
      expect(result).to be_nil
    end
  
    it 'returns a new name if handle_dups is rename' do
      allow(Team).to receive(:generate_team_name).and_return('Renamed_Team')
      result = Team.handle_duplicate(existing_team, 'Existing Team', assignment.id, 'rename', AssignmentTeam)
      expect(result).to eq('Renamed_Team')
    end
  
    it 'returns original name and deletes team if handle_dups is replace' do
      expect(existing_team).to receive(:delete)
      result = Team.handle_duplicate(existing_team, 'Existing Team', assignment.id, 'replace', AssignmentTeam)
      expect(result).to eq('Existing Team')
    end
  
    it 'returns nil for handle_dups insert' do
      result = Team.handle_duplicate(existing_team, 'Existing Team', assignment.id, 'insert', AssignmentTeam)
      expect(result).to be_nil
    end
  end

  describe '#export' do
    it 'writes team names and members to the CSV' do
      team = AssignmentTeam.create!(name: 'ExportTeam', parent_id: assignment.id, assignment_id: assignment.id)
      user = User.create!(name: 'export_user', full_name: 'Export User', email: 'export@example.com', password: 'password', role: role)
      TeamsUser.create!(team: team, user: user)
  
      csv = []
      options = { team_name: 'false' }
  
      Team.export(csv, assignment.id, options, AssignmentTeam)
  
      expect(csv.length).to eq(1)
      expect(csv[0]).to include('ExportTeam', 'export_user')
    end
  end

  describe '#create_team_and_node' do
    it 'creates a new team and team node, and adds specified users to the team' do
      user1 = User.create!(name: 'user_node_1', full_name: 'User 1', email: 'u1@example.com', password: 'password', role: role)
      user2 = User.create!(name: 'user_node_2', full_name: 'User 2', email: 'u2@example.com', password: 'password', role: role)
  
      allow(Team).to receive(:find_parent_entity).with(assignment.id).and_return(assignment)
      allow(TeamNode).to receive(:create)
      allow_any_instance_of(Team).to receive(:add_member).and_return(true)
  
      team = Team.create_team_and_node(assignment.id, [user1.id, user2.id])
  
      expect(team).to be_a(Team)
      expect(team.parent_id).to eq(assignment.id)
      expect(team.name).to match(/Team_\d+/)
    end
  end  

  describe '#find_team_for_user' do
    it 'returns the team for given assignment and user' do
      user = User.create!(name: 'team_user', full_name: 'Team User', email: 'team_user@example.com', password: 'password', role: role)
      team = Team.create!(name: 'FindMeTeam', parent_id: assignment.id, assignment: assignment)
      TeamsUser.create!(user: user, team: team)
  
      result = Team.find_team_for_user(assignment.id, user.id)
      expect(result.first.t_id).to eq(team.id)
    end
  end

  describe '#has_participant?' do
    it 'returns true if the participant is in the team' do
      team = Team.create!(name: 'ParticipantTeam', parent_id: assignment.id, assignment: assignment)
      participant = AssignmentParticipant.create!(
        user: instructor,
        assignment_id: assignment.id,
        handle: 'instructor_handle'
      )

      allow(team).to receive(:participants).and_return([participant])
      expect(team.has_participant?(participant)).to be true
    end

    it 'returns false if the participant is not in the team' do
      team = Team.create!(name: 'NoParticipantTeam', parent_id: assignment.id, assignment: assignment)
      participant = AssignmentParticipant.create!(
        user: instructor,
        assignment_id: assignment.id,
        handle: 'not_in_team'
      )

      allow(team).to receive(:participants).and_return([])
      expect(team.has_participant?(participant)).to be false
    end
  end
end
