import Foundation
import HomePadCore
import Testing
@testable import HomePadUICore

@Suite struct CompanionLayoutPolicyTests {
    @Test func arrangement_whenCompactWidth_thenTabsAtAnyWidth() {
        #expect(CompanionLayoutPolicy.arrangement(isRegularWidth: false, width: 466) == .tabs)
        #expect(CompanionLayoutPolicy.arrangement(isRegularWidth: false, width: 932) == .tabs)
    }

    @Test func arrangement_whenRegularWidth_thenTwoColumnsOnceBothFit() {
        #expect(CompanionLayoutPolicy.arrangement(isRegularWidth: true, width: 626) == .twoColumn)
        #expect(CompanionLayoutPolicy.arrangement(isRegularWidth: true, width: 890) == .twoColumn)
        #expect(CompanionLayoutPolicy.arrangement(isRegularWidth: true, width: 1032) == .twoColumn)
        #expect(CompanionLayoutPolicy.arrangement(isRegularWidth: true, width: 559) == .tabs)
    }

    @Test func sidebarWidth_whenContainerGrows_thenAShareOfItWithinLimits() {
        #expect(CompanionLayoutPolicy.sidebarWidth(forWidth: 626) == 626 * 0.38)
        #expect(CompanionLayoutPolicy.sidebarWidth(forWidth: 560) == 220)
        #expect(CompanionLayoutPolicy.sidebarWidth(forWidth: 1366) == 320)
        #expect(CompanionLayoutPolicy.sidebarWidth(forWidth: .infinity) == 320)
        #expect(CompanionLayoutPolicy.sidebarWidth(forWidth: 626) + CompanionLayoutPolicy.minimumDetailWidth < 626)
    }

    @Test func detail_whenHubIsSelected_thenFirstSectionShowsAndOthersShowThemselves() {
        #expect(CompanionLayoutPolicy.detail(for: .hub) == .beam)
        #expect(CompanionLayoutPolicy.detail(for: .apps) == .apps)
        #expect(CompanionLayoutPolicy.detail(for: .people) == .people)
        #expect(CompanionLayoutPolicy.sidebarSections == [.beam, .apps, .people])
        #expect(CompanionSection.allCases.map(\.id) == ["hub", "beam", "apps", "people"])
    }
}

@Suite struct HubPanePolicyTests {
    @Test func placement_whenPaneCoversTheContainer_thenTogether() {
        #expect(HubPanePolicy.placement(containerWidth: 890, containerHeight: 626, paneWidth: 890, paneHeight: 626) == .together)
        // A safe area takes a little off a pane without dividing the display.
        #expect(HubPanePolicy.placement(containerWidth: 1366, containerHeight: 1024, paneWidth: 1366, paneHeight: 980) == .together)
        #expect(HubPanePolicy.placement(containerWidth: 0, containerHeight: 626, paneWidth: 0, paneHeight: 626) == .together)
    }

    @Test func placement_whenPaneHasOneSideOfAFold_thenApart() {
        #expect(HubPanePolicy.placement(containerWidth: 890, containerHeight: 626, paneWidth: 435, paneHeight: 626) == .apart)
        #expect(HubPanePolicy.placement(containerWidth: 626, containerHeight: 890, paneWidth: 626, paneHeight: 435) == .apart)
    }
}

@Suite struct CanvasObstacleTests {
    private let strip = CanvasFrame(x: 0, y: 0, width: 466, height: 106)

    @Test func insets_whenNothingIsInTheWay_thenZero() {
        #expect(strip.insets(clearing: []) == .zero)
        #expect(strip.insets(clearing: [CanvasFrame(x: 0, y: 300, width: 60, height: 60)]) == .zero)
        #expect(strip.insets(clearing: [CanvasFrame(x: 10, y: 10, width: 0, height: 40)]) == .zero)
    }

    @Test func insets_whenObstacleIsNearAnEdge_thenThatEdgeMovesIn() {
        // A camera in the top trailing corner, wider than it is tall, is cleared from the top.
        #expect(strip.insets(clearing: [CanvasFrame(x: 380, y: 8, width: 70, height: 30)]).top == 38)
        // One close to the trailing edge is cleared from that edge.
        #expect(strip.insets(clearing: [CanvasFrame(x: 430, y: 8, width: 30, height: 90)]).trailing == 36)
        #expect(strip.insets(clearing: [CanvasFrame(x: 4, y: 8, width: 30, height: 90)]).leading == 34)
        #expect(strip.insets(clearing: [CanvasFrame(x: 100, y: 90, width: 200, height: 40)]).bottom == 16)
    }

    @Test func insets_whenSeveralObstacles_thenTheLargestOnEachEdge() {
        let insets = strip.insets(clearing: [
            CanvasFrame(x: 0, y: 0, width: 466, height: 20),
            CanvasFrame(x: 380, y: 8, width: 70, height: 30),
            CanvasFrame(x: 0, y: 0, width: 12, height: 106),
        ])
        #expect(insets == CanvasInsets(top: 38, leading: 12, bottom: 0, trailing: 0))
    }

    @Test func edges_whenSafeAreaGiven_thenFourStripsAlongTheContainer() {
        let safe = CanvasInsets(top: 24, leading: 0, bottom: 20, trailing: 62)
        let edges = CanvasFrame.edges(of: safe, width: 466, height: 678)
        #expect(edges == [
            CanvasFrame(x: 0, y: 0, width: 466, height: 24),
            CanvasFrame(x: 0, y: 658, width: 466, height: 20),
            CanvasFrame(x: 0, y: 0, width: 0, height: 678),
            CanvasFrame(x: 404, y: 0, width: 62, height: 678),
        ])
        let status = CanvasFrame(x: 0, y: 0, width: 466, height: 106)
        #expect(status.insets(clearing: edges) == CanvasInsets(top: 24, leading: 0, bottom: 0, trailing: 62))
    }
}

@Suite struct ChromePanelLayoutTests {
    @Test func panel_whenTallHalf_thenStripOnTopAndWidgetsBelow() {
        let panel = ChromePanelLayout(width: 445, height: 626)
        #expect(panel.unitSide == 445)
        #expect(panel.status == CanvasFrame(x: 0, y: 0, width: 445, height: 445 * 0.16))
        #expect(panel.side == CanvasFrame(x: 0, y: 445 * 0.16, width: 445, height: 626 - 445 * 0.16))
    }

    @Test func panel_whenWideHalfOrNoSpace_thenStillInsideThePane() {
        let wide = ChromePanelLayout(width: 626, height: 445)
        #expect(wide.unitSide == 445)
        #expect(wide.status.width == 626 && wide.side.y == wide.status.height)
        #expect(wide.status.height + wide.side.height == 445)
        let none = ChromePanelLayout(width: -10, height: 0)
        #expect(none.unitSide == 0 && none.status.height == 0 && none.side.height == 0)
    }
}

@Suite struct SidePanelGridTests {
    @Test func grid_whenTallNarrowColumn_thenOneColumnOfThree() {
        // The second column beside a 1024 point canvas on a large iPad.
        let grid = SidePanelGrid(width: 290, height: 858, gap: 24, preferredSide: 403)
        #expect(grid.columns == 1 && grid.rows == 3 && grid.count == 3)
        #expect(grid.tileWidth == 290 && grid.tileHeight == 270)
    }

    @Test func grid_whenHalfOfAFoldedDisplay_thenTwoByTwo() {
        let grid = SidePanelGrid(width: 431, height: 541, gap: 11, preferredSide: 175)
        #expect(grid.columns == 2 && grid.rows == 2 && grid.count == 4)
        #expect(grid.tileWidth == 210 && grid.tileHeight == 265)
    }

    @Test func grid_whenWideHalf_thenTwoByTwoAndAShortStripIsOneRow() {
        let half = SidePanelGrid(width: 612, height: 360, gap: 11, preferredSide: 175)
        #expect(half.columns == 2 && half.rows == 2)
        #expect(half.tileWidth == 300.5 && half.tileHeight == 174.5)
        let strip = SidePanelGrid(width: 610, height: 230, gap: 15, preferredSide: 246)
        #expect(strip.rows == 1 && strip.columns == 3)
    }

    @Test func grid_whenNoSpace_thenOneEmptyTile() {
        let grid = SidePanelGrid(width: 0, height: 0, gap: 10, preferredSide: 175)
        #expect(grid.count == 1 && grid.tileWidth == 0 && grid.tileHeight == 0)
        let negative = SidePanelGrid(width: -40, height: 100, gap: 10, preferredSide: 175)
        #expect(negative.tileWidth == 0)
    }
}

@Suite struct TestViewportTests {
    @Test func viewport_whenTextIsWidthByHeight_thenParsedWithSizeClasses() throws {
        let inner = try #require(TestViewport("626x890"))
        #expect(inner.width == 626 && inner.height == 890)
        #expect(inner.isRegularWidth && inner.isRegularHeight)
        let outer = try #require(TestViewport("466x678"))
        #expect(!outer.isRegularWidth && outer.isRegularHeight)
        let outerOnItsSide = try #require(TestViewport("678x466"))
        #expect(!outerOnItsSide.isRegularWidth && !outerOnItsSide.isRegularHeight)
        let innerOnItsSide = try #require(TestViewport("890x626"))
        #expect(innerOnItsSide.isRegularWidth && innerOnItsSide.isRegularHeight)
    }

    @Test func viewport_whenTextIsMalformed_thenNil() {
        #expect(TestViewport("626") == nil)
        #expect(TestViewport("626x") == nil)
        #expect(TestViewport("axb") == nil)
        #expect(TestViewport("0x890") == nil)
        #expect(TestViewport("626x-1") == nil)
        #expect(TestViewport("626x890x2") == nil)
    }

    @Test func hooks_whenViewportRoleAndFoldSet_thenParsed() {
        let hooks = HubTestHooks(environment: [
            "HOMEPAD_UITEST_VIEWPORT": "890x626",
            "HOMEPAD_UITEST_ROLE": "companion",
            "HOMEPAD_UITEST_FOLD": "1",
        ])
        #expect(hooks.viewport?.width == 890 && hooks.viewport?.height == 626)
        #expect(hooks.role == .companion)
        #expect(hooks.foldsHub)
        let none = HubTestHooks(environment: ["HOMEPAD_UITEST_VIEWPORT": "big", "HOMEPAD_UITEST_ROLE": "server"])
        #expect(none.viewport == nil && none.role == nil && !none.foldsHub)
        #expect(HubTestHooks.none.viewport == nil && HubTestHooks.none.role == nil)
    }
}
