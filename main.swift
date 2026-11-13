import AppKit
import Carbon

struct Port: Decodable { let name: String; let code: Int }
struct MonitorProfile: Decodable {
    let id: String
    let name: String
    let ports: [Port]
    let controls: [String]
}
struct Catalog: Decodable { let schemaVersion: Int; let monitors: [MonitorProfile] }
struct MonitorInfo: Decodable { let profile: String; let model: String; let input: Int? }
struct ControlValue: Decodable {
    let available: Bool
    let value: Int?
    let maximum: Int?
}

struct Bridge {
    static func run(_ arguments: [String]) -> (Int32, Data) {
        let task = Process()
        task.executableURL = Bundle.main.url(forResource: "ddc-bridge", withExtension: nil)
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe; task.standardError = pipe
        let finished = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in finished.signal() }
        do { try task.run() } catch { return (-1, Data(error.localizedDescription.utf8)) }
        if finished.wait(timeout: .now() + 5) == .timedOut {
            task.terminate()
            return (-1, Data("The monitor is not responding. Try its physical input button.".utf8))
        }
        return (task.terminationStatus, pipe.fileHandleForReading.readDataToEndOfFile())
    }
    static func message(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

final class CommitSlider: NSSlider {
    private(set) var isMouseTracking = false
    var onEndTracking: (() -> Void)?
    override func mouseDown(with event: NSEvent) {
        isMouseTracking = true
        super.mouseDown(with: event)
        isMouseTracking = false
        onEndTracking?()
    }
}

final class ControlRow: NSView {
    let kind: String
    private let valueLabel = NSTextField(labelWithString: "—")
    private let slider = CommitSlider(value: 0, minValue: 0, maxValue: 100, target: nil, action: nil)
    private var maximum = 0
    private var confirmedValue: Int?
    private var writePending = false
    var onChange: ((ControlRow, Int) -> Void)?
    init(kind: String) {
        self.kind = kind
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 66))
        let title = NSTextField(labelWithString: kind == "brightness" ? "Brightness" : "Volume")
        title.frame = NSRect(x: 16, y: 40, width: 130, height: 20)
        valueLabel.frame = NSRect(x: 155, y: 40, width: 88, height: 20)
        valueLabel.alignment = .right
        valueLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        slider.frame = NSRect(x: 14, y: 8, width: 232, height: 28)
        slider.target = self; slider.action = #selector(changed)
        slider.isContinuous = true
        slider.onEndTracking = { [weak self] in self?.commit() }
        slider.isEnabled = false
        slider.setAccessibilityLabel(title.stringValue)
        addSubview(title); addSubview(valueLabel); addSubview(slider)
    }
    required init?(coder: NSCoder) { fatalError("Not implemented") }
    func show(_ value: ControlValue?, completingWrite: Bool = false) {
        if completingWrite { writePending = false }
        guard !slider.isMouseTracking, !writePending else { return }
        guard let value, value.available, let current = value.value, let max = value.maximum, max > 0 else {
            maximum = 0; confirmedValue = nil; slider.isEnabled = false; valueLabel.stringValue = "Unavailable"; return
        }
        maximum = max
        confirmedValue = current
        slider.doubleValue = Double(current) * 100 / Double(max)
        slider.isEnabled = true
        valueLabel.stringValue = "\(Int(slider.doubleValue.rounded()))%"
    }
    @objc private func changed() {
        guard maximum > 0 else { return }
        valueLabel.stringValue = "\(Int(slider.doubleValue.rounded()))%"
        if !slider.isMouseTracking { commit() }
    }
    private func commit() {
        guard maximum > 0, slider.isEnabled else { return }
        let target = Int((slider.doubleValue * Double(maximum) / 100).rounded())
        guard target != confirmedValue else { return }
        writePending = true
        slider.isEnabled = false
        onChange?(self, target)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let controlsMenu = NSMenu(title: "Controls")
    private let currentItem = NSMenuItem(title: "Detecting monitor…", action: nil, keyEquivalent: "")
    private var profiles: [MonitorProfile] = []
    private var profile: MonitorProfile?
    private var currentInput: Int?
    private var portItems: [NSMenuItem] = []
    private var rows: [String: ControlRow] = [:]
    private var hotkeys: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private var shortcutsRegistered = true
    private var readingMonitor = false
    private var readingControls = false
    private let worker = DispatchQueue(label: "sk.mk.InputSwitch.ddc")
    private let defaults = UserDefaults.standard
    private var namesWindow: NSWindow?
    private var editingProfile: MonitorProfile?
    private var nameFields: [Int: NSTextField] = [:]

    private func alias(for port: Port, profileID: String) -> String {
        let models = defaults.dictionary(forKey: "portAliasesByModel") as? [String: [String: String]] ?? [:]
        if let names = models[profileID] { return names[String(port.code)] ?? "" }
        if profileID == "asus-pa329cv" {
            return (defaults.dictionary(forKey: "portAliases") as? [String: String])?[String(port.code)] ?? ""
        }
        return ""
    }
    private func displayName(_ port: Port, in model: MonitorProfile) -> String {
        let label = alias(for: port, profileID: model.id)
        return label.isEmpty ? port.name : "\(port.name) (\(label))"
    }
    private func updateLabels() {
        guard let profile else { return }
        for (port, entry) in zip(profile.ports, portItems) {
            entry.title = displayName(port, in: profile)
            entry.state = currentInput == port.code ? .on : .off
        }
        let input = currentInput.map { code in profile.ports.first { $0.code == code }.map { displayName($0, in: profile) } ?? "Input \(code)" }
        currentItem.title = input.map { "\(profile.name) · \($0)" } ?? "\(profile.name) · status unavailable"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let url = Bundle.main.url(forResource: "monitors", withExtension: "json"),
           let data = try? Data(contentsOf: url), let catalog = try? JSONDecoder().decode(Catalog.self, from: data), catalog.schemaVersion == 1 {
            profiles = catalog.monitors
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "display", accessibilityDescription: "MonitorSwitch")
        statusItem.button?.toolTip = "MonitorSwitch"
        menu.delegate = self; controlsMenu.delegate = self
        menu.autoenablesItems = false; controlsMenu.autoenablesItems = false
        rebuildMenu()
        statusItem.menu = menu
        refreshMonitor()
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = self
        if !key.isEmpty { entry.keyEquivalentModifierMask = [.control, .option, .command] }
        return entry
    }
    private func rebuildMenu() {
        menu.removeAllItems(); controlsMenu.removeAllItems(); portItems.removeAll(); rows.removeAll()
        currentItem.isEnabled = false; menu.addItem(currentItem); menu.addItem(.separator())
        if let profile {
            for (index, port) in profile.ports.enumerated() {
                let entry = item(displayName(port, in: profile), #selector(selectPort), key: String(index + 1))
                entry.tag = port.code; portItems.append(entry); menu.addItem(entry)
            }
            menu.addItem(.separator())
            for kind in profile.controls where kind == "brightness" || kind == "volume" {
                let row = ControlRow(kind: kind)
                row.onChange = { [weak self] row, value in self?.setControl(row, value: value) }
                let entry = NSMenuItem(); entry.view = row; controlsMenu.addItem(entry); rows[kind] = row
            }
            if !rows.isEmpty {
                let controls = NSMenuItem(title: "Controls", action: nil, keyEquivalent: "")
                controls.submenu = controlsMenu; menu.addItem(controls); menu.addItem(.separator())
            }
        }
        let names = item("Port Names…", #selector(editNames))
        names.keyEquivalent = ","; names.keyEquivalentModifierMask = [.command]; names.isEnabled = profile != nil
        menu.addItem(names)
        menu.addItem(item("About MonitorSwitch…", #selector(about)))
        menu.addItem(item("Quit MonitorSwitch", #selector(quit)))
        updateLabels(); registerShortcuts()
    }

    func menuWillOpen(_ opening: NSMenu) {
        if opening === controlsMenu { refreshControls() } else if opening === menu { refreshMonitor() }
    }
    private func refreshMonitor() {
        guard !readingMonitor else { return }
        readingMonitor = true
        worker.async {
            let result = Bridge.run(["info"])
            let info = result.0 == 0 ? try? JSONDecoder().decode(MonitorInfo.self, from: result.1) : nil
            DispatchQueue.main.async {
                self.readingMonitor = false
                let previous = self.profile?.id
                self.profile = info.flatMap { data in self.profiles.first { $0.id == data.profile } }
                self.currentInput = info?.input
                if self.profile == nil { self.currentItem.title = "No supported monitor available" }
                if previous != self.profile?.id || self.portItems.isEmpty { self.rebuildMenu() }
                else { self.updateLabels() }
                if CommandLine.arguments.contains("--settings"), self.namesWindow == nil, self.profile != nil { self.editNames() }
            }
        }
    }
    private func refreshControls() {
        guard let profile, !readingControls else { return }
        readingControls = true
        let id = profile.id
        worker.async {
            let result = Bridge.run(["controls", id])
            let values = result.0 == 0 ? try? JSONDecoder().decode([String: ControlValue].self, from: result.1) : nil
            DispatchQueue.main.async {
                self.readingControls = false
                guard self.profile?.id == id else { return }
                for (kind, row) in self.rows { row.show(values?[kind]) }
            }
        }
    }
    private func setControl(_ row: ControlRow, value: Int) {
        guard let profile else { return }
        let id = profile.id, kind = row.kind
        worker.async {
            let result = Bridge.run(["set", id, kind, String(value)])
            let readback = result.0 == 0 ? try? JSONDecoder().decode(ControlValue.self, from: result.1) : nil
            DispatchQueue.main.async {
                guard self.profile?.id == id else { return }
                self.rows[kind]?.show(readback, completingWrite: true)
                if result.0 != 0 { self.showError("Could not change \(kind)", data: result.1) }
            }
        }
    }
    private func showError(_ title: String, data: Data) {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = Bridge.message(data)
        NSApp.activate(ignoringOtherApps: true); alert.runModal()
    }
    @objc private func selectPort(_ sender: NSMenuItem) { select(sender.tag) }
    private func select(_ code: Int) {
        guard let profile, profile.ports.contains(where: { $0.code == code }) else { return }
        let id = profile.id
        currentItem.title = "Switching…"
        worker.async {
            let result = Bridge.run(["set", id, "input", String(code)])
            DispatchQueue.main.async {
                guard self.profile?.id == id else { return }
                if result.0 != 0 { self.showError("Could not change the monitor input", data: result.1) }
                else { self.currentItem.title = "Command sent" }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.refreshMonitor() }
            }
        }
    }
    func selectShortcut(_ index: Int) {
        guard let ports = profile?.ports, ports.indices.contains(index) else { return }
        select(ports[index].code)
    }

    @objc private func editNames() {
        if let namesWindow, namesWindow.isVisible { NSApp.activate(ignoringOtherApps: true); namesWindow.makeKeyAndOrderFront(nil); return }
        guard let profile else { return }
        editingProfile = profile
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 470, height: 155 + profile.ports.count * 34), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Port Names"; window.isReleasedWhenClosed = false; window.isRestorable = false
        let intro = NSTextField(wrappingLabelWithString: "\(profile.name)\nAdd a label in parentheses, such as HDMI 2 (Switch). Leave a field empty to show only the port name.")
        nameFields.removeAll()
        let grid = NSGridView(views: profile.ports.map { port -> [NSView] in
            let field = NSTextField(string: alias(for: port, profileID: profile.id))
            field.placeholderString = "Optional label"; field.setAccessibilityLabel("Label for \(port.name)")
            nameFields[port.code] = field
            return [NSTextField(labelWithString: port.name), field]
        })
        grid.rowSpacing = 10; grid.columnSpacing = 16; grid.column(at: 0).width = 86
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelNames)); cancel.keyEquivalent = "\u{1b}"
        let save = NSButton(title: "Save", target: self, action: #selector(saveNames)); save.keyEquivalent = "\r"
        let buttons = NSStackView(views: [cancel, save]); buttons.spacing = 8
        let stack = NSStackView(views: [intro, grid, buttons]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        guard let content = window.contentView else { return }
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -22),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            intro.widthAnchor.constraint(equalTo: stack.widthAnchor), grid.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttons.trailingAnchor.constraint(equalTo: stack.trailingAnchor)
        ])
        let fields = profile.ports.compactMap { nameFields[$0.code] }
        for (field, next) in zip(fields, fields.dropFirst()) { field.nextKeyView = next }
        fields.last?.nextKeyView = save; window.initialFirstResponder = fields.first
        namesWindow = window; window.center(); NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
    }
    @objc private func cancelNames() { namesWindow?.close() }
    @objc private func saveNames() {
        guard let model = editingProfile else { return }
        var names: [String: String] = [:]
        for port in model.ports {
            let clean = (nameFields[port.code]?.stringValue ?? "").components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            names[String(port.code)] = String(clean.prefix(60))
        }
        var models = defaults.dictionary(forKey: "portAliasesByModel") as? [String: [String: String]] ?? [:]
        models[model.id] = names; defaults.set(models, forKey: "portAliasesByModel")
        updateLabels(); namesWindow?.close()
    }
    @objc private func about() {
        let alert = NSAlert(); alert.messageText = "MonitorSwitch"
        let model = profile?.name ?? "No supported monitor connected"
        let shortcuts = profile.map { model in model.ports.enumerated().map { "⌃⌥⌘\($0.offset + 1) — \(displayName($0.element, in: model))" }.joined(separator: "\n") } ?? ""
        let collision = shortcutsRegistered ? "" : "\n\nA shortcut is in use by another app. You can still use the menu."
        alert.informativeText = "\(model)\n\n\(shortcuts)\n\nBrightness and volume are under Controls. If switching back fails, use the monitor’s input button.\(collision)\n\nDDC transport includes m1ddc, © 2021 waydabber, MIT License."
        alert.addButton(withTitle: "OK"); alert.addButton(withTitle: "Monitor Support…")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn, let url = URL(string: "https://github.com/magmisko/MonitorSwitch/issues/new/choose") { NSWorkspace.shared.open(url) }
    }
    @objc private func quit() { NSApp.terminate(nil) }

    private func registerShortcuts() {
        for key in hotkeys { UnregisterEventHotKey(key) }; hotkeys.removeAll(); shortcutsRegistered = true
        if eventHandler == nil {
            var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let result = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr, id.signature == 0x4d4b4953 else { return OSStatus(eventNotHandledErr) }
                Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue().selectShortcut(Int(id.id) - 1)
                return noErr
            }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
            if result != noErr { shortcutsRegistered = false; return }
        }
        let keys = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
        for index in 0..<(profile?.ports.count ?? 0) where index < keys.count {
            var ref: EventHotKeyRef?
            let result = RegisterEventHotKey(UInt32(keys[index]), UInt32(controlKey | optionKey | cmdKey), EventHotKeyID(signature: 0x4d4b4953, id: UInt32(index + 1)), GetApplicationEventTarget(), 0, &ref)
            if result == noErr, let ref { hotkeys.append(ref) } else { shortcutsRegistered = false }
        }
    }
    func applicationWillTerminate(_ notification: Notification) {
        for key in hotkeys { UnregisterEventHotKey(key) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}

if CommandLine.arguments.contains("--diagnose") {
    let result = Bridge.run(["info"]); print(Bridge.message(result.1)); exit(result.0)
}
let app = NSApplication.shared
let delegate = AppDelegate(); app.delegate = delegate; app.run()
