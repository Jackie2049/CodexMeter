import AppKit

/// Codex mark drawn as vector strokes: the terminal prompt `>_` — the core
/// glyph of the Codex brand. Monochrome via labelColor, so it adapts to the
/// menu bar appearance (white on dark, black on light) like a system icon.
final class CodexGlyphView: NSView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: 13, height: 13)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.setStroke()

        let path = NSBezierPath()
        path.lineWidth = 1.6
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        // Chevron ">"
        path.move(to: NSPoint(x: 3, y: 3))
        path.line(to: NSPoint(x: 9, y: 6.5))
        path.line(to: NSPoint(x: 3, y: 10))

        // Underscore "_"
        path.move(to: NSPoint(x: 8, y: 10))
        path.line(to: NSPoint(x: 12, y: 10))

        path.stroke()
    }
}
