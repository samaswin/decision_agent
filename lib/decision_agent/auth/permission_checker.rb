module DecisionAgent
  module Auth
    class PermissionChecker
      attr_reader :adapter

      def initialize(adapter: nil)
        @adapter = adapter || DefaultAdapter.new
      end

      def can?(user, permission, resource = nil)
        @adapter.can?(user, permission, resource)
      end

      def require_permission!(user, permission, resource = nil)
        unless can?(user, permission, resource)
          raise PermissionDeniedError, "User does not have permission: #{permission}"
        end
        true
      end

      def has_role?(user, role)
        @adapter.has_role?(user, role)
      end

      def require_role!(user, role)
        unless has_role?(user, role)
          raise PermissionDeniedError, "User does not have role: #{role}"
        end
        true
      end

      def active?(user)
        @adapter.active?(user)
      end

      def user_id(user)
        @adapter.user_id(user)
      end

      def user_email(user)
        @adapter.user_email(user)
      end
    end
  end
end

