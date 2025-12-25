module DecisionAgent
  module ABTesting
    # Represents an A/B test configuration for comparing rule versions
    class ABTest
      attr_reader :id, :name, :champion_version_id, :challenger_version_id,
                  :traffic_split, :start_date, :end_date, :status

      # @param name [String] Name of the A/B test
      # @param champion_version_id [String, Integer] ID of the current/champion version
      # @param challenger_version_id [String, Integer] ID of the new/challenger version
      # @param traffic_split [Hash] Traffic distribution (e.g., { champion: 90, challenger: 10 })
      # @param start_date [Time, nil] When the test starts (defaults to now)
      # @param end_date [Time, nil] When the test ends (optional)
      # @param status [String] Test status: running, completed, cancelled, scheduled
      # @param id [String, Integer, nil] Optional ID (for persistence)
      def initialize(
        name:,
        champion_version_id:,
        challenger_version_id:,
        traffic_split: { champion: 90, challenger: 10 },
        start_date: Time.now.utc,
        end_date: nil,
        status: "scheduled",
        id: nil
      )
        @id = id
        @name = name
        @champion_version_id = champion_version_id
        @challenger_version_id = challenger_version_id
        @traffic_split = normalize_traffic_split(traffic_split)
        @start_date = start_date
        @end_date = end_date
        @status = status

        validate!
      end

      # Assign a variant based on traffic split
      # Uses consistent hashing to ensure same user gets same variant
      # @param user_id [String, nil] Optional user identifier for consistent assignment
      # @return [Symbol] :champion or :challenger
      def assign_variant(user_id: nil)
        raise TestNotRunningError, "Test '#{@name}' is not running (status: #{@status})" unless running?

        if user_id
          # Consistent hashing: same user always gets same variant
          hash_value = Digest::SHA256.hexdigest("#{@id}:#{user_id}").to_i(16)
          percentage = hash_value % 100
        else
          # Random assignment
          percentage = rand(100)
        end

        percentage < @traffic_split[:champion] ? :champion : :challenger
      end

      # Get the version ID for the assigned variant
      # @param variant [Symbol] :champion or :challenger
      # @return [String, Integer] The version ID
      def version_for_variant(variant)
        case variant
        when :champion
          @champion_version_id
        when :challenger
          @challenger_version_id
        else
          raise ArgumentError, "Invalid variant: #{variant}. Must be :champion or :challenger"
        end
      end

      # Check if test is currently running
      # @return [Boolean]
      def running?
        return false unless @status == "running"
        return false if @start_date && Time.now.utc < @start_date
        return false if @end_date && Time.now.utc > @end_date

        true
      end

      # Check if test is scheduled to start
      # @return [Boolean]
      def scheduled?
        @status == "scheduled" && @start_date && Time.now.utc < @start_date
      end

      # Check if test is completed
      # @return [Boolean]
      def completed?
        @status == "completed" || (@end_date && Time.now.utc > @end_date)
      end

      # Start the test
      def start!
        raise InvalidStatusTransitionError, "Cannot start test from status: #{@status}" unless can_start?

        @status = "running"
        @start_date = Time.now.utc if @start_date.nil? || @start_date > Time.now.utc
      end

      # Complete the test
      def complete!
        raise InvalidStatusTransitionError, "Cannot complete test from status: #{@status}" unless can_complete?

        @status = "completed"
        @end_date = Time.now.utc
      end

      # Cancel the test
      def cancel!
        raise InvalidStatusTransitionError, "Cannot cancel test from status: #{@status}" if @status == "completed"

        @status = "cancelled"
      end

      # Convert to hash representation
      # @return [Hash]
      def to_h
        {
          id: @id,
          name: @name,
          champion_version_id: @champion_version_id,
          challenger_version_id: @challenger_version_id,
          traffic_split: @traffic_split,
          start_date: @start_date,
          end_date: @end_date,
          status: @status
        }
      end

      private

      def validate!
        raise ValidationError, "Test name is required" if @name.nil? || @name.strip.empty?
        raise ValidationError, "Champion version ID is required" if @champion_version_id.nil?
        raise ValidationError, "Challenger version ID is required" if @challenger_version_id.nil?
        raise ValidationError, "Champion and challenger must be different versions" if @champion_version_id == @challenger_version_id

        validate_traffic_split!
        validate_dates!
        validate_status!
      end

      def validate_traffic_split!
        raise ValidationError, "Traffic split must be a Hash" unless @traffic_split.is_a?(Hash)
        raise ValidationError, "Traffic split must have :champion and :challenger keys" unless @traffic_split.key?(:champion) && @traffic_split.key?(:challenger)

        total = @traffic_split[:champion] + @traffic_split[:challenger]
        raise ValidationError, "Traffic split must sum to 100, got #{total}" unless total == 100

        raise ValidationError, "Traffic percentages must be non-negative" if @traffic_split.values.any?(&:negative?)
      end

      def validate_dates!
        return unless @start_date && @end_date

        raise ValidationError, "End date must be after start date" if @end_date <= @start_date
      end

      def validate_status!
        valid_statuses = %w[scheduled running completed cancelled]
        return if valid_statuses.include?(@status)

        raise ValidationError, "Invalid status: #{@status}. Must be one of: #{valid_statuses.join(', ')}"
      end

      def normalize_traffic_split(split)
        case split
        when Hash
          # Handle both string and symbol keys
          {
            champion: (split[:champion] || split["champion"] || 50).to_i,
            challenger: (split[:challenger] || split["challenger"] || 50).to_i
          }
        when Array
          # Handle array format [90, 10]
          { champion: split[0].to_i, challenger: split[1].to_i }
        else
          raise ValidationError, "Traffic split must be a Hash or Array"
        end
      end

      def can_start?
        %w[scheduled].include?(@status)
      end

      def can_complete?
        %w[running].include?(@status)
      end
    end

    # Custom errors
    class TestNotRunningError < StandardError; end
    class InvalidStatusTransitionError < StandardError; end
  end
end
