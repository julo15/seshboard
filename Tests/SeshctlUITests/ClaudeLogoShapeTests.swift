import Foundation
import SwiftUI
import Testing

@testable import SeshctlUI

@Suite("ClaudeLogoShape")
struct ClaudeLogoShapeTests {

    /// Sanity check: the parsed path must be non-empty and stay within
    /// the requested rect (modulo a small floating-point epsilon). This
    /// catches regressions where a tokenization bug folds adjacent
    /// numbers together and produces wildly out-of-range coordinates.
    @Test("Parsed path bounding rect lies within the requested rect")
    func boundsWithinRequestedRect() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let path = ClaudeLogoShape().path(in: rect)
        let bounds = path.boundingRect

        #expect(!bounds.isEmpty)
        let epsilon: CGFloat = 0.5
        #expect(bounds.minX >= rect.minX - epsilon)
        #expect(bounds.minY >= rect.minY - epsilon)
        #expect(bounds.maxX <= rect.maxX + epsilon)
        #expect(bounds.maxY <= rect.maxY + epsilon)
    }

    /// The mark fills most of its 100×100 viewBox — if the bounds come
    /// back tiny, the parser bailed early on an unsupported command and
    /// only drew a fragment of the path.
    @Test("Parsed path covers the bulk of the viewBox")
    func coversMostOfViewBox() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let bounds = ClaudeLogoShape().path(in: rect).boundingRect

        #expect(bounds.width >= 90)
        #expect(bounds.height >= 90)
    }

    /// Aspect-fit centering: a non-square rect must center the square
    /// mark, not stretch it.
    @Test("Non-square rect centers the mark instead of stretching")
    func nonSquareRectCentersMark() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
        let bounds = ClaudeLogoShape().path(in: rect).boundingRect

        // Drawn at 100×100 in the middle of a 200×100 rect → centered
        // horizontally with ~50pt of slack on each side.
        #expect(abs(bounds.width - 100) < 1)
        #expect(abs(bounds.minX - 50) < 1)
    }
}
