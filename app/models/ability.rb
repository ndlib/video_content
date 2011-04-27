class Ability
  include CanCan::Ability

  def initialize(user)
    user ||= User.new # guest user (not logged in) 
    # Load all Permissions for workflow actions
    user.groups.each do |group|
      group.actions.each do |action|
        if action.permissible_id.nil?
          can action.name.to_sym, action.permissible_type.constantize
        else
          can action.name.to_sym, action.permissible_type.constantize, :id => permissible_id.to_i
        end
      end
    end

    # Defining abilties in the database can be augemented with abilities defined in cancan DSL
    # https://github.com/ryanb/cancan/wiki/Defining-Abilities
    # https://github.com/ryanb/cancan/wiki/Abilities-in-Database

    if user.in_group? :root
      can :manage, :all
      can :masquerade, User
      can :manage_abilities, Group
      cannot :destroy, Group, :for_cancan => true

      EventWorkflow.permissible_actions.each do |action|
        can action, EventWorkflow
      end
    else
      can :read, :all
    end
  end
end