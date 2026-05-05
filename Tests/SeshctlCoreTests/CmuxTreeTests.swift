import Foundation
import Testing

@testable import SeshctlCore

@Suite("CmuxTree - findPaneId")
struct CmuxTreeFindPaneIdTests {
    private static let json = """
        {
          "windows": [
            {
              "workspaces": [
                {
                  "panes": [
                    {
                      "surfaces": [
                        {"id": "S1", "pane_id": "P1"},
                        {"id": "S2", "pane_id": "P1"}
                      ]
                    },
                    {
                      "surfaces": [
                        {"id": "S3", "pane_id": "P2"}
                      ]
                    }
                  ]
                }
              ]
            }
          ]
        }
        """

    @Test("Returns pane_id for surface in first pane")
    func firstPane() {
        #expect(CmuxTree.findPaneId(json: Self.json, surfaceId: "S2") == "P1")
    }

    @Test("Returns pane_id for surface in second pane")
    func secondPane() {
        #expect(CmuxTree.findPaneId(json: Self.json, surfaceId: "S3") == "P2")
    }

    @Test("Returns nil when surface is not present")
    func missingSurface() {
        #expect(CmuxTree.findPaneId(json: Self.json, surfaceId: "S99") == nil)
    }

    @Test("Returns nil for malformed JSON")
    func malformedJSON() {
        #expect(CmuxTree.findPaneId(json: "{not json", surfaceId: "S1") == nil)
    }

    @Test("Walks across multiple windows")
    func multiWindow() {
        let json = """
            {
              "windows": [
                {"workspaces": []},
                {"workspaces": [{"panes": [{"surfaces": [{"id": "X", "pane_id": "PX"}]}]}]}
              ]
            }
            """
        #expect(CmuxTree.findPaneId(json: json, surfaceId: "X") == "PX")
    }
}

@Suite("CmuxTree - surfaceIds(inPane:)")
struct CmuxTreeSurfaceIdsTests {
    private static let json = """
        {
          "windows": [{
            "workspaces": [{
              "panes": [
                {"surfaces": [{"id": "A", "pane_id": "P1"}, {"id": "B", "pane_id": "P1"}]},
                {"surfaces": [{"id": "C", "pane_id": "P2"}]}
              ]
            }]
          }]
        }
        """

    @Test("Returns ids of surfaces in target pane")
    func targetPane() {
        #expect(CmuxTree.surfaceIds(inPane: "P1", treeJSON: Self.json) == ["A", "B"])
    }

    @Test("Returns single id for pane with one surface")
    func singleSurface() {
        #expect(CmuxTree.surfaceIds(inPane: "P2", treeJSON: Self.json) == ["C"])
    }

    @Test("Returns empty for unknown pane")
    func unknownPane() {
        #expect(CmuxTree.surfaceIds(inPane: "P99", treeJSON: Self.json) == [])
    }

    @Test("Returns empty for malformed JSON")
    func malformedJSON() {
        #expect(CmuxTree.surfaceIds(inPane: "P1", treeJSON: "garbage") == [])
    }
}
