class ChangeToPolymorphicAssociationInTeams < ActiveRecord::Migration[8.0]
  def change
    # Remove old assignment and course references
    remove_reference :teams, :assignment, foreign_key: true
    remove_reference :teams, :course, foreign_key: true
  end
end
