require "spec_helper"

RSpec.describe DecisionAgent::Auth::PermissionChecker do
  let(:checker) { DecisionAgent::Auth::PermissionChecker.new }

  describe "#can?" do
    let(:admin_user) do
      DecisionAgent::Auth::User.new(
        email: "admin@example.com",
        password: "password123",
        roles: [:admin]
      )
    end

    let(:editor_user) do
      DecisionAgent::Auth::User.new(
        email: "editor@example.com",
        password: "password123",
        roles: [:editor]
      )
    end

    let(:viewer_user) do
      DecisionAgent::Auth::User.new(
        email: "viewer@example.com",
        password: "password123",
        roles: [:viewer]
      )
    end

    it "returns true if user has permission" do
      expect(checker.can?(admin_user, :write)).to be true
      expect(checker.can?(editor_user, :write)).to be true
      expect(checker.can?(viewer_user, :read)).to be true
    end

    it "returns false if user lacks permission" do
      expect(checker.can?(viewer_user, :write)).to be false
      expect(checker.can?(editor_user, :delete)).to be false
    end

    it "returns false for nil user" do
      expect(checker.can?(nil, :read)).to be false
    end

    it "returns false for inactive user" do
      admin_user.active = false
      expect(checker.can?(admin_user, :read)).to be false
    end
  end

  describe "#require_permission!" do
    let(:user) do
      DecisionAgent::Auth::User.new(
        email: "user@example.com",
        password: "password123",
        roles: [:viewer]
      )
    end

    it "does not raise if user has permission" do
      expect do
        checker.require_permission!(user, :read)
      end.not_to raise_error
    end

    it "raises PermissionDeniedError if user lacks permission" do
      expect do
        checker.require_permission!(user, :write)
      end.to raise_error(DecisionAgent::PermissionDeniedError)
    end
  end

  describe "#has_role?" do
    let(:user) do
      DecisionAgent::Auth::User.new(
        email: "user@example.com",
        password: "password123",
        roles: [:editor]
      )
    end

    it "returns true if user has role" do
      expect(checker.has_role?(user, :editor)).to be true
    end

    it "returns false if user lacks role" do
      expect(checker.has_role?(user, :admin)).to be false
    end

    it "returns false for nil user" do
      expect(checker.has_role?(nil, :editor)).to be false
    end
  end
end

