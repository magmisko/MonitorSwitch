import AppKit
import Carbon

struct Port {
    let name: String
    let code: Int
    let key: String
    let keyCode: UInt32
    static let all: [Port] = [
        Port(name: "USB-C", code: 19, key: "1", keyCode: UInt32(kVK_ANSI_1)),
        Port(name: "DisplayPort", code: 15, key: "2", keyCode: UInt32(kVK_ANSI_2)),
        Port(name: "HDMI 1", code: 17, key: "3", keyCode: UInt32(kVK_ANSI_3)),
        Port(name: "HDMI 2", code: 18, key: "4", keyCode: UInt32(kVK_ANSI_4))
    ]
}

struct Bridge {
    static func run(_ arguments: [String]) -> (Int32, String) {
        let task = Process()
        task.executableURL = Bundle.main.url(forResource: "ddc-bridge", withExtension: nil)
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        let finished = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in finished.signal() }
        do { try task.run() } catch { return (-1, error.localizedDescription) }
        if finished.wait(timeout: .now() + 5) == .timedOut {
            task.terminate()
            return (-1, "The monitor is not responding. Try its physical input button.")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (task.terminationStatus, String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let currentItem = NSMenuItem(title: "ASUS PA329CV", action: nil, keyEquivalent: "")
    private var portItems: [NSMenuItem] = []
    private var hotkeys: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private var busy = false
    private var shortcutsRegistered = true
    private let worker = DispatchQueue(label: "sk.mk.InputSwitch.ddc")
    private let defaults = UserDefaults.standard
    private var currentInput: Int?
    private var namesWindow: NSWindow?
    private var nameFields: [Int: NSTextField] = [:]

    private func alias(for port: Port) -> String {
        (defaults.dictionary(forKey: "portAliases") as? [String: String])?[String(port.code)] ?? ""
    }

    private func displayName(for port: Port) -> String {
        let name = alias(for: port)
        return name.isEmpty ? port.name : "\(port.name) (\(name))"
    }

    private func updateLabels() {
        for (port, entry) in zip(Port.all, portItems) { entry.title = displayName(for: port) }
        if let currentInput {
            let label = Port.all.first { $0.code == currentInput }.map { displayName(for: $0) } ?? "Input \(currentInput)"
            currentItem.title = "ASUS · \(label)"
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        defaults.register(defaults: ["portAliases": [String: String]()])
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "display", accessibilityDescription: "MonitorSwitch")
        statusItem.button?.toolTip = "ASUS PA329CV inputs"
        menu.delegate = self
        menu.addItem(currentItem)
        menu.addItem(.separator())
        for port in Port.all {
            let entry = item(displayName(for: port), #selector(selectPort), key: port.key)
            entry.tag = port.code
            portItems.append(entry)
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        let namesItem = item("Port Names…", #selector(editNames))
        namesItem.keyEquivalent = ","
        namesItem.keyEquivalentModifierMask = [.command]
        menu.addItem(namesItem)
        menu.addItem(item("About MonitorSwitch…", #selector(about)))
        menu.addItem(item("Quit MonitorSwitch", #selector(quit)))
        statusItem.menu = menu
        registerShortcuts()
        refresh()
        if CommandLine.arguments.contains("--settings") { editNames() }
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let result = NSMenuItem(title: title, action: action, keyEquivalent: key)
        result.target = self
        if !key.isEmpty { result.keyEquivalentModifierMask = [.control, .option, .command] }
        return result
    }

    func menuWillOpen(_ menu: NSMenu) { refresh() }

    private func refresh() {
        guard !busy else { return }
        busy = true
        worker.async {
            let result = Bridge.run(["read"])
            DispatchQueue.main.async {
                self.busy = false
                for item in self.portItems { item.state = .off }
                if result.0 == 0, let input = Int(result.1) {
                    self.currentInput = input
                    self.updateLabels()
                    for item in self.portItems { item.state = item.tag == input ? .on : .off }
                } else {
                    self.currentInput = nil
                    self.currentItem.title = "ASUS · status unavailable"
                }
            }
        }
    }

    @objc private func selectPort(_ sender: NSMenuItem) { select(sender.tag) }

    func select(_ input: Int) {
        guard Port.all.contains(where: { $0.code == input }) else { return }
        currentItem.title = "Switching…"
        worker.async {
            let result = Bridge.run(["set", String(input)])
            DispatchQueue.main.async {
                if result.0 != 0 {
                    self.currentItem.title = "Could not switch input"
                    let alert = NSAlert()
                    alert.messageText = "Could not change the monitor input"
                    alert.informativeText = result.1
                    NSApp.activate(ignoringOtherApps: true)
                    alert.runModal()
                } else {
                    self.currentItem.title = "Command sent"
                    for item in self.portItems { item.state = .off }
                    // One readback establishes the actual state after the transition.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.refresh() }
                }
            }
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func editNames() {
        if let namesWindow, namesWindow.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            namesWindow.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 280),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Port Names"
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        let intro = NSTextField(wrappingLabelWithString: "Add a label in parentheses, such as HDMI 2 (Switch). Leave a field empty to show only the port name.")
        intro.font = .systemFont(ofSize: NSFont.systemFontSize)
        nameFields.removeAll()
        let rows: [[NSView]] = Port.all.map { port in
            let label = NSTextField(labelWithString: port.name)
            let field = NSTextField(string: alias(for: port))
            field.placeholderString = "Optional label"
            field.setAccessibilityLabel("Label for \(port.name)")
            nameFields[port.code] = field
            return [label, field]
        }
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 10
        grid.columnSpacing = 16
        grid.column(at: 0).width = 86
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelNames))
        cancel.keyEquivalent = "\u{1b}"
        let save = NSButton(title: "Save", target: self, action: #selector(saveNames))
        save.keyEquivalent = "\r"
        let buttons = NSStackView(views: [cancel, save])
        buttons.spacing = 8
        let stack = NSStackView(views: [intro, grid, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        guard let content = window.contentView else { return }
        content.addSubview(stack)
        // Activate constraints only after every view shares a common ancestor.
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -22),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            intro.widthAnchor.constraint(equalTo: stack.widthAnchor),
            grid.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttons.trailingAnchor.constraint(equalTo: stack.trailingAnchor)
        ])
        let fields = Port.all.compactMap { nameFields[$0.code] }
        for (field, next) in zip(fields, fields.dropFirst()) { field.nextKeyView = next }
        fields.last?.nextKeyView = save
        window.initialFirstResponder = fields.first
        namesWindow = window
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func cancelNames() { namesWindow?.close() }

    @objc private func saveNames() {
        var aliases: [String: String] = [:]
        for port in Port.all {
            let value = nameFields[port.code]?.stringValue ?? ""
            let clean = value.components(separatedBy: .newlines).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            aliases[String(port.code)] = String(clean.prefix(60))
        }
        defaults.set(aliases, forKey: "portAliases")
        updateLabels()
        namesWindow?.close()
    }
    @objc private func about() {
        let alert = NSAlert()
        alert.messageText = "MonitorSwitch"
        let shortcuts = Port.all.map { "⌃⌥⌘\($0.key) — \(displayName(for: $0))" }.joined(separator: "\n")
        let collision = shortcutsRegistered ? "" : "\n\nA shortcut is already in use by another app. You can still switch inputs from the menu."
        alert.informativeText = "ASUS PA329CV\n\n\(shortcuts)\n\nIf switching back through USB-C fails, use the monitor’s physical input button.\(collision)\n\nDDC transport is based on m1ddc, © 2021 waydabber, MIT License."
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func registerShortcuts() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handlerResult = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr, id.signature == 0x4d4b4953 else { return OSStatus(eventNotHandledErr) }
            let app = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            app.select(Int(id.id))
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        guard handlerResult == noErr else { shortcutsRegistered = false; return }
        for port in Port.all {
            var reference: EventHotKeyRef?
            let result = RegisterEventHotKey(port.keyCode, UInt32(controlKey | optionKey | cmdKey),
                EventHotKeyID(signature: 0x4d4b4953, id: UInt32(port.code)), GetApplicationEventTarget(), 0, &reference)
            if result == noErr, let reference { hotkeys.append(reference) }
            else { shortcutsRegistered = false }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        for key in hotkeys { UnregisterEventHotKey(key) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}

if CommandLine.arguments.contains("--diagnose") {
    let result = Bridge.run(["read"])
    print(result.1)
    exit(result.0)
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
