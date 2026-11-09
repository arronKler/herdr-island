import Foundation

/// The detail preview is read-only, so it behaves like a terminal tail: new
/// output may move the viewport only while the reader is already at the tail.
/// Content growth must not be mistaken for the reader leaving the tail; only
/// an upward scroll is.
public enum TerminalScrollFollow {
    /// `offset` is the content's top in the scroll view's coordinate space
    /// (0 at the top, negative after scrolling down). The content's bottom is
    /// `offset + contentHeight`; at the tail it meets the viewport's bottom.
    public static func isAtBottom(
        offset: CGFloat,
        contentHeight: CGFloat,
        viewportHeight: CGFloat,
        tolerance: CGFloat = 8
    ) -> Bool {
        offset + contentHeight <= viewportHeight + tolerance
    }

    public static func scrolledUp(
        offset: CGFloat,
        previousOffset: CGFloat?,
        tolerance: CGFloat = 1
    ) -> Bool {
        guard let previousOffset else { return false }
        return offset > previousOffset + tolerance
    }
}
