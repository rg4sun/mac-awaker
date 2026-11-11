import AppKit

enum ReminderSize: String, CaseIterable, Hashable {
    case standard
    case compact

    var dimensions: NSSize {
        switch self {
        case .standard: return NSSize(width: 258, height: 76)
        case .compact: return NSSize(width: 80, height: 80)
        }
    }

    var menuTitle: String {
        switch self {
        case .standard: return "Standard (258 × 76 pt)"
        case .compact: return "Compact circle (80 × 80 pt)"
        }
    }
}

/// Paints only the rounded card, leaving the window's corner pixels transparent.
/// A visual-effect view can paint an opaque rectangular backing beyond its
/// rounded layer; an explicitly drawn surface avoids that white corner fringe.
private final class ReminderBackdropView: NSView {
    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.cornerRadius = 16
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("ReminderBackdropView is created programmatically.")
    }

    override func draw(_ dirtyRect: NSRect) {
        // Explicitly clear the complete backing surface before painting the
        // inset border. No rectangular window material is left in the corners.
        NSColor.clear.setFill()
        bounds.fill(using: .copy)

        let outline = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            xRadius: 15.5,
            yRadius: 15.5
        )
        NSColor.windowBackgroundColor.setFill()
        outline.fill()
        NSColor.systemOrange.withAlphaComponent(0.5).setStroke()
        outline.lineWidth = 1
        outline.stroke()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// A small, optional reminder remains visible when an application hides the
/// menu bar. The panel does not take keyboard focus from the user's document.
final class ReminderPanel: NSPanel {
    var onStop: (() -> Void)?
    private(set) var reminderSize = ReminderSize.compact
    private let timeLabel = NSTextField(labelWithString: "Until switched off")
    private let standardView = ReminderBackdropView(frame: NSRect(origin: .zero, size: ReminderSize.standard.dimensions))
    private let compactView = CompactReminderView(frame: NSRect(origin: .zero, size: ReminderSize.compact.dimensions))

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: ReminderSize.compact.dimensions),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none

        let backdrop = standardView
        contentView = compactView
        compactView.onStop = { [weak self] in self?.onStop?() }

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: "Keep awake is on")
        icon.contentTintColor = .systemOrange
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 23, weight: .semibold)

        let titleLabel = NSTextField(labelWithString: "AWAKE IS ON")
        titleLabel.font = .systemFont(ofSize: 12, weight: .bold)
        titleLabel.textColor = .labelColor
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        timeLabel.textColor = .secondaryLabelColor

        let stopButton = NSButton(title: "Stop", target: self, action: #selector(stopClicked))
        stopButton.bezelStyle = .rounded
        stopButton.controlSize = .small
        stopButton.setAccessibilityLabel("Stop keeping the Mac awake")

        let labels = NSStackView(views: [titleLabel, timeLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 4

        [icon, labels, stopButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            backdrop.addSubview($0)
        }

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor, constant: 16),
            icon.centerYAnchor.constraint(equalTo: backdrop.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 26),
            icon.heightAnchor.constraint(equalToConstant: 26),
            labels.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            labels.centerYAnchor.constraint(equalTo: backdrop.centerYAnchor),
            stopButton.leadingAnchor.constraint(greaterThanOrEqualTo: labels.trailingAnchor, constant: 12),
            stopButton.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor, constant: -14),
            stopButton.centerYAnchor.constraint(equalTo: backdrop.centerYAnchor)
        ])
    }

    /// Change only the presentation. Keep the panel's lower-right anchor when
    /// resizing, and keep both sizes inside the current display's usable area.
    func setSize(_ size: ReminderSize) {
        guard size != reminderSize else { return }
        let previousFrame = frame
        let screen = self.screen ?? NSScreen.screens.first { $0.frame.intersects(previousFrame) }
        var nextFrame = NSRect(
            x: previousFrame.maxX - size.dimensions.width,
            y: previousFrame.minY,
            width: size.dimensions.width,
            height: size.dimensions.height
        )
        if let visibleFrame = screen?.visibleFrame {
            nextFrame.origin.x = min(max(nextFrame.minX, visibleFrame.minX), visibleFrame.maxX - nextFrame.width)
            nextFrame.origin.y = min(max(nextFrame.minY, visibleFrame.minY), visibleFrame.maxY - nextFrame.height)
        }
        reminderSize = size
        contentView = size == .compact ? compactView : standardView
        setFrame(nextFrame, display: false)
        contentView?.layoutSubtreeIfNeeded()
        invalidateShadow()
    }

    func show(session: AwakeSession, size: ReminderSize) {
        setSize(size)
        update(session: session)
        if !isVisible {
            // Put the first reminder on the display where the user is working.
            // A user can then drag it to a less distracting position.
            let pointer = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) }
                ?? NSScreen.main
            if let frame = screen?.visibleFrame {
                setFrameOrigin(NSPoint(x: frame.maxX - self.frame.width - 24, y: frame.minY + 24))
            }
            orderFrontRegardless()
        }
    }

    func update(session: AwakeSession) {
        let remaining = session.remaining
        let elapsed = session.elapsed
        compactView.update(elapsed: elapsed, remaining: remaining)
        if let remaining {
            timeLabel.stringValue = "\(Self.clock(remaining)) remaining"
        } else {
            timeLabel.stringValue = "On for \(Self.clock(elapsed.rounded(.down)))"
        }
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    @objc private func stopClicked() {
        onStop?()
    }
}
