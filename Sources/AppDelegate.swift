import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let session = AwakeSession()
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let statusRow = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let elapsedRow = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let detailRow = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var toggleRow: NSMenuItem!
    private var reminderRow: NSMenuItem!
    private var reminderSizeRows: [ReminderSize: NSMenuItem] = [:]
    private var timer: Timer?
    private var stopObservers: [(NotificationCenter, NSObjectProtocol)] = []
    private let reminder = ReminderPanel()
    private var lastStopReason = "Your normal screen settings apply."
    private var renderedBadgeKey: String?

    private var showsReminder: Bool {
        get { UserDefaults.standard.bool(forKey: "showFloatingReminder") }
        set { UserDefaults.standard.set(newValue, forKey: "showFloatingReminder") }
    }

    private var reminderSize: ReminderSize {
        get {
            ReminderSize(rawValue: UserDefaults.standard.string(forKey: "reminderSize") ?? "") ?? .compact
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "reminderSize") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The preference controls the reminder only. An active session is never
        // saved or restored: each application launch begins with keep-awake off.
        UserDefaults.standard.register(defaults: [
            "showFloatingReminder": true,
            "reminderSize": ReminderSize.compact.rawValue
        ])
        // Reserve one compact, fixed-width slot in both states. Neither enabling
        // keep-awake nor a longer timer may push the item towards the notch.
        statusItem = NSStatusBar.system.statusItem(withLength: StatusBadge.statusItemLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        buildMenu()
        reminder.onStop = { [weak self] in self?.stop(reason: "Stopped by you.") }
        observeSessionBoundaries()
        render()
    }

    private func buildMenu() {
        menu.delegate = self
        menu.autoenablesItems = false
        statusRow.isEnabled = false
        elapsedRow.isEnabled = false
        detailRow.isEnabled = false
        menu.addItem(statusRow)
        menu.addItem(elapsedRow)
        menu.addItem(detailRow)
        menu.addItem(.separator())

        toggleRow = addItem("Keep awake until switched off", action: #selector(toggleAwake))
        for minutes in [10, 30, 60] {
            let item = addItem("Keep awake for \(minutes) minutes", action: #selector(startTimed(_:)))
            item.tag = minutes
        }
        menu.addItem(.separator())
        reminderRow = addItem("Show floating reminder", action: #selector(toggleReminder))
        let sizeRow = NSMenuItem(title: "Reminder size", action: nil, keyEquivalent: "")
        let sizeMenu = NSMenu(title: "Reminder size")
        sizeMenu.autoenablesItems = false
        sizeMenu.delegate = self
        for size in ReminderSize.allCases {
            let item = NSMenuItem(title: size.menuTitle, action: #selector(chooseReminderSize(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = size.rawValue
            sizeMenu.addItem(item)
            reminderSizeRows[size] = item
        }
        sizeRow.submenu = sizeMenu
        menu.addItem(sizeRow)
        menu.addItem(.separator())

        let note = NSMenuItem(title: "Left-click: on/off  ·  Right-click: options", action: nil, keyEquivalent: "")
        note.isEnabled = false
        menu.addItem(note)
        addItem("About Mac Awaker", action: #selector(showAbout))
        addItem("Quit Mac Awaker", action: #selector(quit), key: "q")
    }

    @discardableResult
    private func addItem(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    @objc private func statusClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            toggleAwake()
        }
    }

    private func showMenu() {
        guard let button = statusItem.button else { return }
        // Attach the menu only for this interaction, so the next ordinary click
        // remains a true one-click toggle rather than opening the menu.
        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func toggleAwake() {
        session.refresh()
        if session.isActive {
            stop(reason: "Stopped by you.")
        } else {
            start()
        }
    }

    @objc private func startTimed(_ sender: NSMenuItem) {
        start(for: TimeInterval(sender.tag * 60))
    }

    private func start(for duration: TimeInterval? = nil) {
        do {
            try session.start(for: duration)
            timer?.invalidate()
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                self?.tick()
            }
            // Common modes keep the countdown accurate while a menu is open.
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
            render()
        } catch {
            render()
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Keep awake could not start"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    private func stop(reason: String) {
        session.stop()
        timer?.invalidate()
        timer = nil
        lastStopReason = reason
        render()
    }

    private func tick() {
        if !session.refresh() {
            stop(reason: "The keep-awake session has ended.")
        } else {
            render()
        }
    }

    private func render() {
        guard let button = statusItem?.button else { return }
        let active = session.isActive

        let elapsedDescription = "On for \(ReminderPanel.clock(session.elapsed.rounded(.down)))"
        let remainingDescription = session.remaining.map { "\(ReminderPanel.clock($0)) remaining" }
        let timingDescription = remainingDescription.map { "\(elapsedDescription). \($0)" } ?? elapsedDescription
        let badgeKey = active ? "on" : "off"
        if renderedBadgeKey != badgeKey {
            // An explicit image avoids black-on-black system tinting, including
            // when the application appearance differs from the menu bar.
            button.attributedTitle = NSAttributedString(string: "")
            button.contentTintColor = nil
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
            button.image = StatusBadge.image(active: active)
            renderedBadgeKey = badgeKey
        }
        button.toolTip = active
            ? "Mac Awaker is ON. \(timingDescription). Left-click to stop. Right-click for options."
            : "Mac Awaker is OFF. Left-click to keep the screen awake. Right-click for options."
        button.setAccessibilityLabel(active ? "Mac Awaker is on. \(timingDescription). Click to stop." : "Mac Awaker is off. Click to start.")

        statusRow.title = active ? "Keep awake is ON" : "Keep awake is OFF"
        // Elapsed time has its own row for every active session, including
        // timed sessions. The same one-second timer updates it while the menu
        // is tracking; the menu bar itself always contains just the icon.
        elapsedRow.title = elapsedDescription
        elapsedRow.isHidden = !active
        if let deadline = session.deadline, let remainingDescription {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            detailRow.title = "\(remainingDescription) · Ends at \(formatter.string(from: deadline))"
        } else {
            detailRow.title = active ? "Until switched off" : lastStopReason
        }
        toggleRow.title = active ? "Stop keeping awake" : "Keep awake until switched off"
        reminderRow.state = showsReminder ? .on : .off
        let selectedSize = reminderSize
        for (size, item) in reminderSizeRows {
            item.state = size == selectedSize ? .on : .off
        }
        reminder.setSize(selectedSize)

        if active && showsReminder {
            reminder.show(session: session, size: selectedSize)
        } else {
            reminder.orderOut(nil)
        }
    }

    private func observeSessionBoundaries() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification,
                     NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            observeStop(on: workspace, name: name, reason: "Stopped when your Mac slept or your session changed.")
        }

        // macOS sends distributed notifications for manual locking and screen
        // saver activation. There is deliberately no observer that reactivates
        // keep-awake after the user unlocks the computer.
        let distributed = DistributedNotificationCenter.default()
        for name in ["com.apple.screenIsLocked", "com.apple.screensaver.didstart"] {
            observeStop(on: distributed, name: Notification.Name(name), reason: "Stopped when the screen locked or the screen saver started.")
        }
    }

    private func observeStop(on centre: NotificationCenter, name: Notification.Name, reason: String) {
        let observer = centre.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.session.isActive else { return }
            self.stop(reason: reason)
        }
        stopObservers.append((centre, observer))
    }

    func menuWillOpen(_ menu: NSMenu) {
        if session.isActive && !session.refresh() {
            stop(reason: "The keep-awake session has ended.")
        } else {
            render()
        }
    }

    @objc private func toggleReminder() {
        showsReminder.toggle()
        render()
    }

    @objc private func chooseReminderSize(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let size = ReminderSize(rawValue: rawValue) else { return }
        reminderSize = size
        render()
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Mac Awaker"
        alert.informativeText = "Keep reference material visible while you read.\n\nLeft-click the menu bar icon to switch keep-awake on or off. Right-click for timers and Reminder size.\n\nIn the compact circle, click the sun to stop and drag the edge to move. The ring shows time remaining during a timed session; an unlimited session shows elapsed time.\n\nYour screen, sleep and password settings stay unchanged. Manual locking and closing the lid still work. The app starts switched off."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        session.stop()
        timer?.invalidate()
        reminder.orderOut(nil)
        for (centre, observer) in stopObservers {
            centre.removeObserver(observer)
        }
    }
}
