import AppKit
import CoreText

/// An eighty-point reminder whose text follows the inside of its circular rim.
/// Only the centre is a button; the surrounding surface remains available for
/// dragging the non-activating panel without stopping the keep-awake session.
final class CompactReminderView: NSView {
    var onStop: (() -> Void)?
    private(set) var displayTime = "00:00"
    private(set) var remainingFraction: CGFloat = 1
    private var isTimed = false
    private let stopButton = NSButton()

    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = true
        layer?.cornerRadius = 40
        setAccessibilityRole(.group)

        stopButton.isBordered = false
        stopButton.bezelStyle = .regularSquare
        stopButton.imagePosition = .imageOnly
        stopButton.image = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 23, weight: .semibold))
        stopButton.contentTintColor = .systemOrange
        stopButton.target = self
        stopButton.action = #selector(stopClicked)
        stopButton.toolTip = "Stop keeping awake"
        stopButton.setAccessibilityLabel("Stop keeping the Mac awake")
        stopButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stopButton)
        NSLayoutConstraint.activate([
            stopButton.widthAnchor.constraint(equalToConstant: 40),
            stopButton.heightAnchor.constraint(equalToConstant: 32),
            stopButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            stopButton.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 1)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("CompactReminderView is created programmatically.")
    }

    func update(elapsed: TimeInterval, remaining: TimeInterval?) {
        isTimed = remaining != nil
        // Round remaining time upwards and elapsed time downwards. In particular,
        // a newly started unlimited session should display 00:00 rather than 00:01.
        displayTime = ReminderPanel.clock(remaining ?? elapsed.rounded(.down))
        if let remaining {
            let total = elapsed + remaining
            remainingFraction = total > 0 ? CGFloat(min(1, max(0, remaining / total))) : 0
        } else {
            remainingFraction = 1
        }
        let timing = isTimed ? "\(displayTime) remaining" : "On for \(displayTime)"
        toolTip = "Awake is on. \(timing). Click the sun to stop; drag the edge to move."
        setAccessibilityLabel("Awake is on. \(timing).")
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill(using: .copy)
        let centre = NSPoint(x: bounds.midX, y: bounds.midY)
        let surface = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5))
        NSColor.windowBackgroundColor.setFill()
        surface.fill()

        let radius = min(bounds.width, bounds.height) / 2 - 2
        let track = NSBezierPath(ovalIn: NSRect(
            x: centre.x - radius, y: centre.y - radius,
            width: radius * 2, height: radius * 2
        ))
        NSColor.systemOrange.withAlphaComponent(0.2).setStroke()
        track.lineWidth = 2
        track.stroke()

        if remainingFraction > 0 {
            let progress: NSBezierPath
            if remainingFraction >= 1 {
                // Use an explicit circle for unlimited sessions, rather than
                // relying on how an arc normalises equal start/end angles.
                progress = NSBezierPath(ovalIn: track.bounds)
            } else {
                progress = NSBezierPath()
                progress.appendArc(
                    withCenter: centre,
                    radius: radius,
                    startAngle: 90,
                    endAngle: 90 - 360 * remainingFraction,
                    clockwise: true
                )
            }
            progress.lineWidth = 2.2
            progress.lineCapStyle = .round
            NSColor.systemOrange.setStroke()
            progress.stroke()
        }

        drawCurvedText(
            "AWAKE IS ON", centre: centre, radius: 26, upper: true,
            font: .systemFont(ofSize: 10.5, weight: .semibold), tracking: 0.2
        )
        drawCurvedText(
            displayTime, centre: centre, radius: 26, upper: false,
            font: .monospacedDigitSystemFont(ofSize: 11, weight: .medium), tracking: 0.25
        )
    }

    /// Core Text draws each character on its own tangent, preserving upright
    /// text along the lower arc. The timer contains digits and colons only: its
    /// position distinguishes it from the title without a direction arrow.
    private func drawCurvedText(
        _ text: String, centre: NSPoint, radius: CGFloat,
        upper: Bool, font: NSFont, tracking: CGFloat
    ) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): NSColor.labelColor.cgColor
        ]
        let characters = text.map { character -> (CTLine, CGFloat) in
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: String(character), attributes: attributes))
            return (line, CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))
        }
        let width = characters.reduce(CGFloat(0)) { $0 + $1.1 }
            + tracking * CGFloat(max(0, characters.count - 1))
        var offset = -width / 2

        for (line, advance) in characters {
            let distance = offset + advance / 2
            let angle = upper ? .pi / 2 - distance / radius : 3 * .pi / 2 + distance / radius
            let rotation = upper ? angle - .pi / 2 : angle + .pi / 2
            context.saveGState()
            context.translateBy(x: centre.x + cos(angle) * radius, y: centre.y + sin(angle) * radius)
            context.rotate(by: rotation)
            context.textMatrix = .identity
            context.textPosition = CGPoint(x: -advance / 2, y: 0)
            CTLineDraw(line, context)
            context.restoreGState()
            offset += advance + tracking
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    @objc private func stopClicked() {
        onStop?()
    }
}
