import AppKit

/// The Codex mark (codex-new): a rounded-square frame containing the
/// terminal prompt `>_`. Redrawn as native bezier strokes in labelColor so
/// it adapts to the menu bar appearance like a system icon — coordinates
/// follow the original 24-unit SVG, scaled to the view's bounds.
final class CodexGlyphView: NSView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: 13, height: 13)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.setStroke()

        let scale = NSAffineTransform()
        scale.scale(by: bounds.width / 24)
        scale.concat()

        // Rounded-square frame
        let frame = NSBezierPath(
            roundedRect: NSRect(x: 2.4, y: 2.4, width: 19.2, height: 19.2),
            xRadius: 6.8, yRadius: 6.8)
        frame.lineWidth = 2.2
        frame.stroke()

        // Chevron ">"
        let chevron = NSBezierPath()
        chevron.lineWidth = 1.7
        chevron.lineCapStyle = .round
        chevron.lineJoinStyle = .round
        chevron.move(to: NSPoint(x: 8.3, y: 8.8))
        chevron.line(to: NSPoint(x: 10.9, y: 12))
        chevron.line(to: NSPoint(x: 8.3, y: 15.2))
        chevron.stroke()

        // Underscore "_"
        let dash = NSBezierPath()
        dash.lineWidth = 1.8
        dash.lineCapStyle = .round
        dash.move(to: NSPoint(x: 12.1, y: 14.5))
        dash.line(to: NSPoint(x: 16.9, y: 14.5))
        dash.stroke()
    }
}
