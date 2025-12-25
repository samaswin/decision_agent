require "spec_helper"
require "decision_agent/ab_testing/ab_test"

RSpec.describe DecisionAgent::ABTesting::ABTest do
  describe "#initialize" do
    it "creates a valid A/B test with default values" do
      test = described_class.new(
        name: "Test A vs B",
        champion_version_id: "v1",
        challenger_version_id: "v2"
      )

      expect(test.name).to eq("Test A vs B")
      expect(test.champion_version_id).to eq("v1")
      expect(test.challenger_version_id).to eq("v2")
      expect(test.traffic_split).to eq({ champion: 90, challenger: 10 })
      expect(test.status).to eq("scheduled")
    end

    it "accepts custom traffic split as hash" do
      test = described_class.new(
        name: "Custom Split",
        champion_version_id: "v1",
        challenger_version_id: "v2",
        traffic_split: { champion: 70, challenger: 30 }
      )

      expect(test.traffic_split).to eq({ champion: 70, challenger: 30 })
    end

    it "accepts custom traffic split as array" do
      test = described_class.new(
        name: "Array Split",
        champion_version_id: "v1",
        challenger_version_id: "v2",
        traffic_split: [80, 20]
      )

      expect(test.traffic_split).to eq({ champion: 80, challenger: 20 })
    end

    it "raises error if traffic split doesn't sum to 100" do
      expect do
        described_class.new(
          name: "Bad Split",
          champion_version_id: "v1",
          challenger_version_id: "v2",
          traffic_split: { champion: 60, challenger: 30 }
        )
      end.to raise_error(DecisionAgent::ValidationError, /must sum to 100/)
    end

    it "raises error if champion and challenger are the same" do
      expect do
        described_class.new(
          name: "Same Versions",
          champion_version_id: "v1",
          challenger_version_id: "v1"
        )
      end.to raise_error(DecisionAgent::ValidationError, /must be different/)
    end

    it "raises error if name is empty" do
      expect do
        described_class.new(
          name: "",
          champion_version_id: "v1",
          challenger_version_id: "v2"
        )
      end.to raise_error(DecisionAgent::ValidationError, /name is required/)
    end
  end

  describe "#assign_variant" do
    let(:test) do
      described_class.new(
        name: "Test",
        champion_version_id: "v1",
        challenger_version_id: "v2",
        traffic_split: { champion: 90, challenger: 10 },
        status: "running",
        id: 123
      )
    end

    it "assigns champion or challenger based on traffic split" do
      assignments = 1000.times.map { test.assign_variant }
      champion_count = assignments.count { |v| v == :champion }
      challenger_count = assignments.count { |v| v == :challenger }

      # With 90/10 split, expect roughly 900/100
      expect(champion_count).to be_between(850, 950)
      expect(challenger_count).to be_between(50, 150)
    end

    it "assigns same variant to same user consistently" do
      user_id = "user_123"
      variants = 10.times.map { test.assign_variant(user_id: user_id) }

      expect(variants.uniq.size).to eq(1)
    end

    it "assigns different users to different variants based on split" do
      assignments = 1000.times.map { |i| test.assign_variant(user_id: "user_#{i}") }
      champion_count = assignments.count { |v| v == :champion }
      challenger_count = assignments.count { |v| v == :challenger }

      expect(champion_count).to be_between(850, 950)
      expect(challenger_count).to be_between(50, 150)
    end

    it "raises error if test is not running" do
      test = described_class.new(
        name: "Not Running",
        champion_version_id: "v1",
        challenger_version_id: "v2",
        status: "completed"
      )

      expect do
        test.assign_variant
      end.to raise_error(DecisionAgent::ABTesting::TestNotRunningError)
    end
  end

  describe "#version_for_variant" do
    let(:test) do
      described_class.new(
        name: "Test",
        champion_version_id: "champion_v1",
        challenger_version_id: "challenger_v2"
      )
    end

    it "returns champion version ID for :champion variant" do
      expect(test.version_for_variant(:champion)).to eq("champion_v1")
    end

    it "returns challenger version ID for :challenger variant" do
      expect(test.version_for_variant(:challenger)).to eq("challenger_v2")
    end

    it "raises error for invalid variant" do
      expect do
        test.version_for_variant(:invalid)
      end.to raise_error(ArgumentError, /Invalid variant/)
    end
  end

  describe "#running?" do
    it "returns true when status is running and within date range" do
      test = described_class.new(
        name: "Test",
        champion_version_id: "v1",
        challenger_version_id: "v2",
        status: "running",
        start_date: Time.now.utc - 3600,
        end_date: Time.now.utc + 3600
      )

      expect(test.running?).to be true
    end

    it "returns false when status is not running" do
      test = described_class.new(
        name: "Test",
        champion_version_id: "v1",
        challenger_version_id: "v2",
        status: "completed"
      )

      expect(test.running?).to be false
    end

    it "returns false when start date is in future" do
      test = described_class.new(
        name: "Test",
        champion_version_id: "v1",
        challenger_version_id: "v2",
        status: "running",
        start_date: Time.now.utc + 3600
      )

      expect(test.running?).to be false
    end

    it "returns false when end date has passed" do
      test = described_class.new(
        name: "Test",
        champion_version_id: "v1",
        challenger_version_id: "v2",
        status: "running",
        start_date: Time.now.utc - 7200,
        end_date: Time.now.utc - 3600
      )

      expect(test.running?).to be false
    end
  end

  describe "status transitions" do
    it "can start a scheduled test" do
      test = described_class.new(
        name: "Test",
        champion_version_id: "v1",
        challenger_version_id: "v2",
        status: "scheduled"
      )

      expect { test.start! }.not_to raise_error
      expect(test.status).to eq("running")
    end

    it "can complete a running test" do
      test = described_class.new(
        name: "Test",
        champion_version_id: "v1",
        challenger_version_id: "v2",
        status: "running"
      )

      expect { test.complete! }.not_to raise_error
      expect(test.status).to eq("completed")
    end

    it "can cancel a test" do
      test = described_class.new(
        name: "Test",
        champion_version_id: "v1",
        challenger_version_id: "v2",
        status: "running"
      )

      expect { test.cancel! }.not_to raise_error
      expect(test.status).to eq("cancelled")
    end

    it "raises error when trying invalid status transition" do
      test = described_class.new(
        name: "Test",
        champion_version_id: "v1",
        challenger_version_id: "v2",
        status: "completed"
      )

      expect do
        test.start!
      end.to raise_error(DecisionAgent::ABTesting::InvalidStatusTransitionError)
    end
  end

  describe "#to_h" do
    it "returns hash representation" do
      test = described_class.new(
        name: "Test",
        champion_version_id: "v1",
        challenger_version_id: "v2",
        id: 123
      )

      hash = test.to_h

      expect(hash[:id]).to eq(123)
      expect(hash[:name]).to eq("Test")
      expect(hash[:champion_version_id]).to eq("v1")
      expect(hash[:challenger_version_id]).to eq("v2")
      expect(hash[:status]).to eq("scheduled")
    end
  end
end
