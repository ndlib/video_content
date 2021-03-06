require 'mediashelf/active_fedora_helper'

# Workflow is an ActiveRecord counterpart to a ActiveFedora model. There is a 1:1 relationship.
class Workflow < ActiveRecord::Base

  include MediaShelf::ActiveFedoraHelper

  has_many :actions, :as => :permissible
  has_many :permissions, :through => :actions

  validates_presence_of :pid

  # NOTE although it is possible to grant CanCan permissions on a instance by instance basis
  # it is not currently implemented. If it IS enabled individual permissions will need to be
  # recored in the database.
  # after_create :publish_permissible_actions

  def self.control_classes
    [ EventWorkflow, MasterWorkflow, DerivativeWorkflow ]
  end

  # All programmatically significant actions; actions that should be registered with CanCan.
  def self.permissible_actions
    @@permissible_actions ||= self.workflow_actions + self.state_event_names
  end

  # CRUD actions that can be performed on Workflow Control Calsses -- used with CanCan.
  def self.workflow_actions
    self.control_classes.collect{|klass| klass.workflow_actions}
  end

  def self.state_event_names
    state_machine.events.collect{|e| e.name}
  end

  def self.state_names
    state_machine.states.collect{|s| s.name}
  end

  def self.state_query_methods
    state_machine.states.collect{|s| "#{s.name.to_s}?".to_sym }
  end

  # All actions enforced by Hydra::RightsMetadata via Rolemapper
  # Types derived from Hydra::AccessControlsEnforcement
  def self.hydra_roles
    @@hydra_roles ||= self.show_actions + self.edit_actions
  end

  def self.hydra_role_names
    @@hydra_role_names ||= hydra_roles.collect{|a| a.to_s }
  end

  # Edit actions enforced by Hydra::RightsMetadata via RoleMapper.
  def self.edit_actions
    self.control_classes.collect{|klass| klass.edit_actions}.flatten
  end

  # Read actions enforced by Hydra::RightsMetadata via RoleMapper.
  def self.show_actions
    self.control_classes.collect{|klass| klass.show_actions}.flatten
  end

  def self.create_class_level_actions
    self.permissible_actions.collect{ |action_name| Action.find_or_create_by_name_and_type(action_name.to_s, self.name) }
  end

  def refresh_permissible_actions
    # Ensure that an Action is available for all permissible_actions
    self.class.permissible_actions.each do |action|
      Action.create(:name => action.to_s, :permissible_id => self.id, :permissible_type => self.class.name)
    end
  end
  alias_method :publish_permissible_actions, :refresh_permissible_actions

  def parent
    nil
  end

  def restrict_editing_to_archival_groups?
    false
  end

  def restrict_editing_to_archival_fields?
    false
  end

  def abilities_affected_by_state_change
    []
  end

  def get_to_users(to_opts={})
    to_users = []

    abilities_affected_by_state_change.each do |ability|
      current_users = User.logins_permitted_to_perform_action(ability.to_s)
      current_users.each do |current_user|
        to_users << current_user
      end
    end
    
    to_users.flatten.map! {|user| "#{user}@nd.edu"}
    to_users = to_users | get_to_group_users(to_opts[:group]) if to_opts[:group]
    logger.debug("to_users: #{to_users.inspect}")
    to_users
  end

  def get_to_group_users(group_name)
    group = Group.find_by_name(group_name)
    group.nil? ? [] : group.users.map {|user| "#{user}@nd.edu"}
  end

  state_machine :state, :initial => :created do
    state :created do
    end

    state :archived do
    end
  end
end
