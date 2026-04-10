# frozen_string_literal: true

# Phase 3 RBAC integration specs.
# Covers:
#   - Permission matrix: every role × every permission (including all 5 built-in roles)
#   - Role-check matrix: every role × has_role? for every role name
#   - Negative tests: nil / unauthenticated user raises PermissionDeniedError, not NotImplementedError
#   - DeviseCanCanAdapter end-to-end with a stub user+roles model
#   - PunditAdapter end-to-end with a stub resource policy
#   - Integration scenario: Viewer can read but cannot approve; Approver can approve but cannot write
#   - PermissionChecker#require_permission! integration

require "spec_helper"
require_relative "../../lib/decision_agent/auth/rbac_adapter"
require_relative "../../lib/decision_agent/auth/permission_checker"
require_relative "../../lib/decision_agent/auth/user"
require_relative "../../lib/decision_agent/auth/role"
require_relative "../../lib/decision_agent/errors"

ALL_PERMISSIONS = %i[read write delete approve deploy manage_users audit].freeze

# Role → expected permission set (mirrors Role::ROLES)
ROLE_PERMISSION_MAP = {
  admin: %i[read write delete approve deploy manage_users audit],
  editor: %i[read write],
  viewer: %i[read],
  auditor: %i[read audit],
  approver: %i[read approve]
}.freeze

RSpec.describe "RBAC Integration" do
  # ── Helpers ──────────────────────────────────────────────────────────────

  # Build a DecisionAgent::Auth::User with the given roles
  def build_user(id:, roles:, active: true)
    DecisionAgent::Auth::User.new(
      id: id,
      email: "#{id}@example.com",
      password: "password123",
      roles: roles,
      active: active
    )
  end

  # ── DefaultAdapter: full permission × role matrix ─────────────────────────

  describe DecisionAgent::Auth::DefaultAdapter do
    let(:adapter) { described_class.new }

    ROLE_PERMISSION_MAP.each do |role, granted|
      context "role: #{role}" do
        let(:user) { build_user(id: role.to_s, roles: [role]) }

        ALL_PERMISSIONS.each do |permission|
          if granted.include?(permission)
            it "grants :#{permission}" do
              expect(adapter.can?(user, permission)).to be true
            end
          else
            it "denies :#{permission}" do
              expect(adapter.can?(user, permission)).to be false
            end
          end
        end

        it "has_role?(#{role}) returns true" do
          expect(adapter.has_role?(user, role)).to be true
        end

        (ROLE_PERMISSION_MAP.keys - [role]).each do |other_role|
          it "has_role?(#{other_role}) returns false" do
            expect(adapter.has_role?(user, other_role)).to be false
          end
        end
      end
    end

    # ── Negative tests: nil / inactive user ─────────────────────────────────

    context "with a nil (unauthenticated) user" do
      it "can? returns false for every permission" do
        ALL_PERMISSIONS.each do |perm|
          expect(adapter.can?(nil, perm)).to be false
        end
      end

      it "has_role? returns false for every role" do
        ROLE_PERMISSION_MAP.each_key do |role|
          expect(adapter.has_role?(nil, role)).to be false
        end
      end
    end

    context "with an inactive user" do
      let(:user) { build_user(id: "inactive", roles: [:admin], active: false) }

      it "can? returns false even for roles that would grant the permission" do
        ALL_PERMISSIONS.each do |perm|
          expect(adapter.can?(user, perm)).to be false
        end
      end
    end

    # ── PermissionChecker integration ────────────────────────────────────────

    describe "PermissionChecker with DefaultAdapter" do
      let(:checker) { DecisionAgent::Auth::PermissionChecker.new(adapter: adapter) }

      it "require_permission! raises PermissionDeniedError (not NotImplementedError) for nil user" do
        expect do
          checker.require_permission!(nil, :read)
        end.to raise_error(DecisionAgent::PermissionDeniedError)
          .and not_raise_error(NotImplementedError)
      end

      it "require_permission! raises PermissionDeniedError for insufficiently privileged user" do
        viewer = build_user(id: "viewer1", roles: [:viewer])
        expect do
          checker.require_permission!(viewer, :write)
        end.to raise_error(DecisionAgent::PermissionDeniedError)
      end

      it "require_permission! returns true when the user has the permission" do
        admin = build_user(id: "admin1", roles: [:admin])
        expect(checker.require_permission!(admin, :manage_users)).to be true
      end

      it "require_role! raises PermissionDeniedError (not NotImplementedError) for nil user" do
        expect do
          checker.require_role!(nil, :viewer)
        end.to raise_error(DecisionAgent::PermissionDeniedError)
          .and not_raise_error(NotImplementedError)
      end
    end
  end

  # ── DeviseCanCanAdapter: end-to-end with stub user + ability ──────────────

  describe DecisionAgent::Auth::DeviseCanCanAdapter do
    # Stub user model that mimics Devise's active_for_authentication? method
    let(:stub_user_class) do
      Struct.new(:id, :email, :active_for_authentication?, :roles, keyword_init: true)
    end

    let(:active_user)   { stub_user_class.new(id: 1, email: "u@e.com", active_for_authentication?: true,  roles: []) }
    let(:inactive_user) { stub_user_class.new(id: 2, email: "x@e.com", active_for_authentication?: false, roles: []) }

    # Stub CanCanCan-like Ability class
    let(:ability_class) do
      Class.new do
        def initialize(user)
          @user = user
        end

        def can?(action, _resource)
          granted = {
            admin: %i[read create destroy approve deploy manage audit],
            editor: %i[read create],
            viewer: %i[read],
            approver: %i[read approve]
          }
          roles = @user.respond_to?(:roles) ? Array(@user.roles).map(&:to_sym) : []
          roles.any? { |r| granted.fetch(r, []).include?(action) }
        end
      end
    end

    let(:adapter) { described_class.new(ability_class: ability_class) }

    context "with an active viewer user" do
      let(:user) { stub_user_class.new(id: 3, email: "v@e.com", active_for_authentication?: true, roles: [:viewer]) }

      it "grants :read" do
        expect(adapter.can?(user, :read)).to be true
      end

      it "denies :write (mapped to :create in CanCanCan)" do
        expect(adapter.can?(user, :write)).to be false
      end

      it "denies :approve" do
        expect(adapter.can?(user, :approve)).to be false
      end
    end

    context "with an active approver user" do
      let(:user) { stub_user_class.new(id: 4, email: "a@e.com", active_for_authentication?: true, roles: [:approver]) }

      it "grants :approve" do
        expect(adapter.can?(user, :approve)).to be true
      end

      it "denies :write" do
        expect(adapter.can?(user, :write)).to be false
      end
    end

    context "with a nil user" do
      it "returns false for every permission without raising NotImplementedError" do
        ALL_PERMISSIONS.each do |perm|
          expect { adapter.can?(nil, perm) }.not_to raise_error
          expect(adapter.can?(nil, perm)).to be false
        end
      end
    end

    context "with an inactive user" do
      it "returns false regardless of roles" do
        user = stub_user_class.new(id: 5, email: "i@e.com", active_for_authentication?: false, roles: [:admin])
        expect(adapter.can?(user, :read)).to be false
      end
    end

    describe "#has_role?" do
      let(:user_with_roles) do
        role_struct = Struct.new(:name, :to_s) { alias_method :to_s, :name } # rubocop:disable Lint/StructNewOverride
        stub_user_class.new(
          id: 6, email: "r@e.com",
          active_for_authentication?: true,
          roles: [role_struct.new(:admin, "admin")]
        )
      end

      it "returns true when the user has the role (via roles.name)" do
        expect(adapter.has_role?(user_with_roles, :admin)).to be true
      end

      it "returns false for a role the user does not have" do
        expect(adapter.has_role?(user_with_roles, :viewer)).to be false
      end

      it "returns false for nil user" do
        expect(adapter.has_role?(nil, :admin)).to be false
      end
    end
  end

  # ── PunditAdapter: end-to-end with stub resource policy ──────────────────

  describe DecisionAgent::Auth::PunditAdapter do
    let(:adapter) { described_class.new }

    # Stub resource with a named policy class
    let(:resource_class) do
      Class.new do
        def self.name
          "DecisionRule"
        end
      end
    end

    let(:resource) { resource_class.new }

    # Stub policy: viewers can show, approvers can approve, editors can create
    let(:policy_class) do
      Class.new do
        attr_reader :user, :record

        def initialize(user, record)
          @user   = user
          @record = record
        end

        def show
          role?(:viewer) || role?(:editor) || role?(:approver) || role?(:admin)
        end

        def create
          role?(:editor) || role?(:admin)
        end

        def approve
          role?(:approver) || role?(:admin)
        end

        private

        def role?(role)
          Array(@user.roles).map(&:to_sym).include?(role)
        end
      end
    end

    let(:stub_user_class) do
      Struct.new(:id, :email, :active?, :roles, keyword_init: true)
    end

    before do
      stub_const("DecisionRulePolicy", policy_class)
    end

    context "with a viewer user" do
      let(:user) { stub_user_class.new(id: 10, email: "v@e.com", active?: true, roles: [:viewer]) }

      it "grants :read (mapped to :show in Pundit)" do
        expect(adapter.can?(user, :read, resource)).to be true
      end

      it "denies :write (mapped to :create)" do
        expect(adapter.can?(user, :write, resource)).to be false
      end

      it "denies :approve" do
        expect(adapter.can?(user, :approve, resource)).to be false
      end
    end

    context "with an approver user" do
      let(:user) { stub_user_class.new(id: 11, email: "a@e.com", active?: true, roles: [:approver]) }

      it "grants :read" do
        expect(adapter.can?(user, :read, resource)).to be true
      end

      it "grants :approve" do
        expect(adapter.can?(user, :approve, resource)).to be true
      end

      it "denies :write" do
        expect(adapter.can?(user, :write, resource)).to be false
      end
    end

    context "with an editor user" do
      let(:user) { stub_user_class.new(id: 12, email: "e@e.com", active?: true, roles: [:editor]) }

      it "grants :write" do
        expect(adapter.can?(user, :write, resource)).to be true
      end

      it "denies :approve" do
        expect(adapter.can?(user, :approve, resource)).to be false
      end
    end

    context "with a nil user" do
      it "returns false for every permission without raising NotImplementedError" do
        ALL_PERMISSIONS.each do |perm|
          expect { adapter.can?(nil, perm, resource) }.not_to raise_error
          expect(adapter.can?(nil, perm, resource)).to be false
        end
      end
    end

    context "with an inactive user" do
      let(:user) { stub_user_class.new(id: 13, email: "i@e.com", active?: false, roles: [:admin]) }

      it "denies all permissions" do
        expect(adapter.can?(user, :read, resource)).to be false
      end
    end
  end

  # ── Integration scenario: Viewer vs Approver decision flow ───────────────

  describe "decision flow integration scenario" do
    let(:default_adapter) { DecisionAgent::Auth::DefaultAdapter.new }
    let(:checker)         { DecisionAgent::Auth::PermissionChecker.new(adapter: default_adapter) }

    let(:viewer)   { build_user(id: "viewer_u",   roles: [:viewer]) }
    let(:approver) { build_user(id: "approver_u", roles: [:approver]) }
    let(:editor)   { build_user(id: "editor_u",   roles: [:editor]) }

    it "Viewer can read a decision rule" do
      expect(checker.can?(viewer, :read)).to be true
    end

    it "Viewer cannot approve a decision rule" do
      expect(checker.can?(viewer, :approve)).to be false
      expect do
        checker.require_permission!(viewer, :approve)
      end.to raise_error(DecisionAgent::PermissionDeniedError)
    end

    it "Approver can approve a decision rule" do
      expect(checker.can?(approver, :approve)).to be true
      expect(checker.require_permission!(approver, :approve)).to be true
    end

    it "Approver cannot write (edit) rules" do
      expect(checker.can?(approver, :write)).to be false
      expect do
        checker.require_permission!(approver, :write)
      end.to raise_error(DecisionAgent::PermissionDeniedError)
    end

    it "Editor can write rules" do
      expect(checker.can?(editor, :write)).to be true
    end

    it "Editor cannot approve rules" do
      expect(checker.can?(editor, :approve)).to be false
    end
  end
end

# Custom matcher helper used inline above
RSpec::Matchers.define :not_raise_error do |error_class = StandardError|
  match do |block|
    block.call
    true
  rescue error_class
    false
  end

  def supports_block_expectations?
    true
  end

  failure_message { "expected block not to raise #{error_class}" }
end
