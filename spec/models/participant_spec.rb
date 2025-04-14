require 'rails_helper'

RSpec.describe Participant, type: :model do
  describe "associations" do
    it "belongs to a user" do
      role = create(:role, :student)
      institution = create(:institution)
      user = create(:user, role: role, institution: institution)

      assignment = create(:assignment)
      participant = Participant.new(user: user, assignment: assignment)

      expect(participant.user).to eq(user)
    end

    it "belongs to an assignment" do
      role = create(:role, :student)
      institution = create(:institution)
      user = create(:user, role: role, institution: institution)

      assignment = create(:assignment)
      participant = Participant.new(user: user, assignment: assignment)

      expect(participant.assignment).to eq(assignment)
    end

    it "can optionally belong to a team" do
      role = create(:role, :student)
      institution = create(:institution)
      user = create(:user, role: role, institution: institution)

      assignment = create(:assignment)
      team = create(:team)
      participant = Participant.new(user: user, assignment: assignment, team: team)

      expect(participant.team).to eq(team)
    end

    it "can have many join_team_requests" do
      role = create(:role, :student)
      institution = create(:institution)
      user = create(:user, role: role, institution: institution)

      assignment = create(:assignment)
      participant = create(:participant, user: user, assignment: assignment)

      request1 = JoinTeamRequest.create(participant: participant)
      request2 = JoinTeamRequest.create(participant: participant)

      expect(participant.join_team_requests).to match_array([request1, request2])
    end
  end

  describe "validations" do
    it "is invalid without a user" do
      assignment = create(:assignment)
      participant = Participant.new(user: nil, assignment: assignment)

      expect(participant).not_to be_valid
      expect(participant.errors[:user]).to include("must exist")
    end

    it "is invalid without an assignment" do
      role = create(:role, :student)
      institution = create(:institution)
      user = create(:user, role: role, institution: institution)

      participant = Participant.new(user: user, assignment: nil)

      expect(participant).not_to be_valid
      expect(participant.errors[:assignment]).to include("must exist")
    end
  end

  describe "#fullname" do
    it "returns the full name of the associated user" do
      role = create(:role, :student)
      institution = create(:institution)
      user = create(:user, role: role, institution: institution, full_name: "Jane Doe")

      assignment = create(:assignment)
      participant = Participant.new(user: user, assignment: assignment)

      expect(participant.fullname).to eq("Jane Doe")
    end
  end
end
