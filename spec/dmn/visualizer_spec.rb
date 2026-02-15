# frozen_string_literal: true

require "spec_helper"
require "decision_agent/dmn/visualizer"

RSpec.describe DecisionAgent::Dmn::Visualizer do
  let(:tree) do
    root = DecisionAgent::Dmn::TreeNode.new(id: "root", label: "Start", condition: "age >= 18")
    child1 = DecisionAgent::Dmn::TreeNode.new(id: "child1", label: "Adult", decision: "approve")
    child2 = DecisionAgent::Dmn::TreeNode.new(id: "child2", label: "Minor", decision: "reject")
    root.add_child(child1)
    root.add_child(child2)
    DecisionAgent::Dmn::DecisionTree.new(id: "tree1", name: "Age Check", root: root)
  end

  let(:graph) do
    graph = DecisionAgent::Dmn::DecisionGraph.new(id: "graph1", name: "Test Graph")
    node1 = DecisionAgent::Dmn::DecisionNode.new(id: "base_score", name: "Base Score", decision_logic: "42")
    node2 = DecisionAgent::Dmn::DecisionNode.new(id: "final_decision", name: "Final Decision", decision_logic: "100")
    node2.add_dependency("base_score")
    graph.add_decision(node1)
    graph.add_decision(node2)
    graph
  end

  describe ".tree_to_svg" do
    it "generates valid SVG markup" do
      svg = described_class.tree_to_svg(tree)

      expect(svg).to include("<svg")
      expect(svg).to include("</svg>")
      expect(svg).to include("Start")
      expect(svg).to include("Adult")
      expect(svg).to include("Minor")
    end

    it "includes arrowhead markers" do
      svg = described_class.tree_to_svg(tree)

      expect(svg).to include("arrowhead")
      expect(svg).to include("<marker")
    end
  end

  describe ".tree_to_dot" do
    it "generates valid DOT format" do
      dot = described_class.tree_to_dot(tree)

      expect(dot).to include("digraph decision_tree")
      expect(dot).to include("root")
      expect(dot).to include("child1")
      expect(dot).to include("child2")
      expect(dot).to include("->")
    end

    it "marks leaf nodes with lightgreen" do
      dot = described_class.tree_to_dot(tree)

      expect(dot).to include("lightgreen")
    end
  end

  describe ".tree_to_mermaid" do
    it "generates valid Mermaid syntax" do
      mermaid = described_class.tree_to_mermaid(tree)

      expect(mermaid).to include("graph TD")
      expect(mermaid).to include("root")
      expect(mermaid).to include("-->")
    end
  end

  describe ".graph_to_svg" do
    it "generates valid SVG markup with decision nodes" do
      svg = described_class.graph_to_svg(graph)

      expect(svg).to include("<svg")
      expect(svg).to include("</svg>")
      expect(svg).to include("Base Score")
      expect(svg).to include("Final Decision")
    end

    it "draws edges for dependencies" do
      svg = described_class.graph_to_svg(graph)

      expect(svg).to include("<line")
    end
  end

  describe ".graph_to_dot" do
    it "generates valid DOT format" do
      dot = described_class.graph_to_dot(graph)

      expect(dot).to include("digraph decision_graph")
      expect(dot).to include("base_score")
      expect(dot).to include("final_decision")
      expect(dot).to include("->")
    end
  end

  describe ".graph_to_mermaid" do
    it "generates valid Mermaid syntax" do
      mermaid = described_class.graph_to_mermaid(graph)

      expect(mermaid).to include("graph TD")
      expect(mermaid).to include("base_score")
      expect(mermaid).to include("final_decision")
      expect(mermaid).to include("-->")
    end
  end
end
