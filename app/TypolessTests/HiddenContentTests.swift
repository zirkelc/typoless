import Testing
@testable import Typoless

/**
 A field that shows more than its text says must never be rewritten whole.

 Slack found this one. A message ending in a smile reports its value as the
 sentence *without* the emoji, and `kAXNumberOfCharacters` agrees with the short
 version, so no count and no comparison can tell that anything is missing. The
 subtree says it plainly: an `AXStaticText` with the words, and an `AXImage`
 described as "smile emoji" beside it.
 */
struct HiddenContentTests {
    @Test(arguments: [
        ["AXStaticText"],
        ["AXGroup", "AXStaticText"],
        ["AXGroup", "AXStaticText", "AXStaticText"],
        ["AXList", "AXListMarker", "AXStaticText"],
        [],
    ])
    func `a field made only of text may be rewritten`(_ roles: [String]) {
        // Arrange
        let subtree = roles

        // Act
        let lossy = HiddenContent.isLossy(roles: subtree)

        // Assert
        #expect(lossy == false)
    }

    /** The first row is Slack's composer, exactly as it reports itself. */
    @Test(arguments: [
        ["AXGroup", "AXStaticText", "AXImage"],
        ["AXImage"],
        ["AXGroup", "AXStaticText", "AXButton"],
        ["AXGroup", "AXStaticText", "AXLink"],
        ["AXStaticText", "AXMenuButton"],
    ])
    func `a field holding anything else is left alone`(_ roles: [String]) {
        // Arrange
        let subtree = roles

        // Act
        let lossy = HiddenContent.isLossy(roles: subtree)

        // Assert
        #expect(lossy == true)
    }
}
