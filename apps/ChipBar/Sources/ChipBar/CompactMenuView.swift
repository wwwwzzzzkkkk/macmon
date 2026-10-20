import AppKit
import ChipBarCore

/// Drawing inside the native status button keeps its click handling and highlight.
@MainActor final class CompactMenuView: NSView {
    private var readouts: [MenuReadout] = []
    private var widths: [String: CGFloat] = [:]
    private var showsLogo = true
    private let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
    private let labelFont = NSFont.systemFont(ofSize: 7, weight: .medium)
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(_ next: [MenuReadout], showsLogo: Bool) -> CGFloat {
        if next.map(\.id) != readouts.map(\.id) || self.showsLogo != showsLogo { widths = [:] }
        readouts = next; self.showsLogo = showsLogo
        for item in next {
            let top = (item.top as NSString).size(withAttributes: [.font: valueFont]).width
            let bottom = (item.bottom as NSString).size(withAttributes: [.font: item.pairedValues ? valueFont : labelFont]).width
            // Reserve each column independently so a changing rate never shifts its neighbours.
            widths[item.id] = max(widths[item.id] ?? 0, ceil(max(22, max(top, bottom))))
        }
        needsDisplay = true
        let columns = next.reduce(CGFloat(0)) { $0 + (widths[$1.id] ?? 22) }
        let gaps = CGFloat(max(0, next.count - 1)) * 9
        return max(24, 8 + columns + gaps + (showsLogo ? (next.isEmpty ? 10 : 20) : 0))
    }

    override func draw(_ dirtyRect: NSRect) {
        let highlighted = (superview as? NSStatusBarButton)?.cell?.isHighlighted == true
        let foreground = highlighted ? NSColor.selectedMenuItemTextColor : NSColor.labelColor
        let secondary = foreground.withAlphaComponent(highlighted ? 0.85 : 0.68)
        let rowY = (bounds.height - 20) / 2
        var x: CGFloat = readouts.isEmpty && showsLogo ? (bounds.width - 10) / 2 : 4
        if showsLogo {
            let y = (bounds.height - 13) / 2
            let bolt = NSBezierPath()
            bolt.move(to: NSPoint(x: x + 7, y: y))
            bolt.line(to: NSPoint(x: x, y: y + 8))
            bolt.line(to: NSPoint(x: x + 4, y: y + 8))
            bolt.line(to: NSPoint(x: x + 2, y: y + 13))
            bolt.line(to: NSPoint(x: x + 10, y: y + 5))
            bolt.line(to: NSPoint(x: x + 6, y: y + 5))
            bolt.close(); foreground.setFill(); bolt.fill()
            x += readouts.isEmpty ? 10 : 20
        }
        if readouts.isEmpty, !showsLogo {
            drawText("···", x: 0, y: (bounds.height - 12) / 2, width: bounds.width,
                     font: .systemFont(ofSize: 12), color: foreground)
        }
        for (index, item) in readouts.enumerated() {
            let width = widths[item.id] ?? 22
            drawText(item.top, x: x, y: rowY, width: width, font: valueFont, color: foreground)
            drawText(item.bottom, x: x, y: rowY + 10, width: width,
                     font: item.pairedValues ? valueFont : labelFont,
                     color: item.pairedValues ? foreground : secondary)
            x += width
            if index < readouts.count - 1 {
                secondary.withAlphaComponent(0.22).setFill()
                NSRect(x: x + 4, y: (bounds.height - 14) / 2, width: 0.5, height: 14).fill()
                x += 9
            }
        }
    }

    private func drawText(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        (text as NSString).draw(in: NSRect(x: x, y: y, width: width, height: 12),
                               withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    }
}
