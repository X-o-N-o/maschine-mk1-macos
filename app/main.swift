// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026 the maschine-mk1-macos contributors
//
// MK1 Bridge – menu bar app for the Native Instruments Maschine MK1 on macOS.
//
// Starts and supervises the mk1-midi daemon (Python, bundled in the app), which
// talks to the MK1 directly over USB: pads, knobs and buttons -> MIDI; LEDs and
// displays <- feedback from your DAW. The daemon handles hot-plugging itself;
// this app keeps it alive (restart after a crash or sleep), shows its status
// and controls it with signals (SIGUSR1 = toggle MIDI mode, SIGUSR2 = panic,
// SIGHUP = reload config).

import AppKit
import Darwin
import ServiceManagement

// MARK: - Paths

enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let support = home.appendingPathComponent("Library/Application Support/MK1Bridge", isDirectory: true)
    static let python = support.appendingPathComponent("venv/bin/python3")
    static let logs = home.appendingPathComponent("Library/Logs/MK1Bridge", isDirectory: true)
    static let config = home.appendingPathComponent(".config/mk1-midi/config.json")
    static var daemonScript: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("daemon/mk1_midi.py")
    }
}

// MARK: - Log

final class LogFile {
    static let shared = LogFile()
    private let queue = DispatchQueue(label: "mk1bridge.log")
    private var handle: FileHandle?
    private var written = 0
    private let url = Paths.logs.appendingPathComponent("mk1bridge.log")
    private let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private init() {
        try? FileManager.default.createDirectory(at: Paths.logs, withIntermediateDirectories: true)
        reopen()
    }

    func write(_ line: String) {
        queue.async {
            if self.written > 5_000_000 { self.rotate() }
            let data = Data("[\(self.stamp.string(from: Date()))] \(line)\n".utf8)
            self.handle?.write(data)
            self.written += data.count
        }
    }

    private func reopen() {
        let fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        handle = fd >= 0 ? FileHandle(fileDescriptor: fd, closeOnDealloc: true) : nil
        written = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue ?? 0
    }

    private func rotate() {
        handle = nil
        let old = Paths.logs.appendingPathComponent("mk1bridge.1.log")
        try? FileManager.default.removeItem(at: old)
        try? FileManager.default.moveItem(at: url, to: old)
        reopen()
    }
}

func log(_ message: String) { LogFile.shared.write(message) }

// MARK: - Daemon supervision

final class DaemonSupervisor {
    enum Run: Equatable { case stopped, running, restarting(in: Int) }

    private(set) var run: Run = .stopped
    private(set) var deviceConnected = false
    private(set) var midiMode = false
    private(set) var lastProblem: String?
    var onChange: (() -> Void)?

    private var process: Process?
    private var wanted = false
    private var restartRequested = false
    private var backoff: TimeInterval = 1
    private var startedAt = Date.distantPast
    private var pending: DispatchWorkItem?
    private var lineBuffer = Data()

    var pid: pid_t? { process?.isRunning == true ? process?.processIdentifier : nil }

    func start() {
        wanted = true
        backoff = 1
        spawn()
    }

    func restart() {
        guard wanted else { return start() }
        pending?.cancel()
        if let p = process, p.isRunning {
            restartRequested = true
            terminate(p)
        } else {
            spawn()
        }
    }

    func send(_ sig: Int32) {
        if let pid { kill(pid, sig) }
    }

    func shutdownNow() {
        wanted = false
        pending?.cancel()
        guard let p = process, p.isRunning else { return }
        p.terminate()   // SIGTERM: daemon blanks LEDs/displays and releases the device
        let deadline = Date().addingTimeInterval(3)
        while p.isRunning && Date() < deadline { usleep(50_000) }
        if p.isRunning { kill(p.processIdentifier, SIGKILL) }
    }

    private func spawn() {
        pending = nil
        guard wanted, process == nil else { return }
        guard let script = Paths.daemonScript, FileManager.default.fileExists(atPath: script.path) else {
            fail("Daemon missing from the app bundle – run build.sh again")
            return
        }
        guard FileManager.default.isExecutableFile(atPath: Paths.python.path) else {
            fail("Python environment missing (\(Paths.python.path)) – run build.sh again")
            return
        }

        let p = Process()
        p.executableURL = Paths.python
        p.arguments = ["-u", script.path]
        p.currentDirectoryURL = script.deletingLastPathComponent()
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        p.standardInput = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            DispatchQueue.main.async { self?.consume(data) }
        }
        p.terminationHandler = { [weak self] proc in
            pipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async { self?.exited(proc) }
        }

        do {
            try p.run()
            process = p
            startedAt = Date()
            run = .running
            lastProblem = nil
            log("Daemon started (PID \(p.processIdentifier))")
        } catch {
            fail("Could not start daemon: \(error.localizedDescription)")
            return
        }
        onChange?()
    }

    private func consume(_ data: Data) {
        guard !data.isEmpty else { return }
        lineBuffer.append(data)
        while let nl = lineBuffer.firstIndex(of: 0x0A) {
            let line = String(decoding: lineBuffer[lineBuffer.startIndex..<nl], as: UTF8.self)
            lineBuffer.removeSubrange(lineBuffer.startIndex...nl)
            handle(line)
        }
    }

    private func handle(_ line: String) {
        log("daemon: \(line)")
        switch line {
        case "connected":
            deviceConnected = true
            lastProblem = nil
        case "disconnected", "device lost":
            deviceConnected = false
            midiMode = false
        case "MIDI mode on":
            midiMode = true
        case "MIDI mode off":
            midiMode = false
        default:
            if line.hasPrefix("cannot open Maschine MK1") {
                lastProblem = String(line.dropFirst("cannot open Maschine MK1: ".count))
            } else if line.hasPrefix("Traceback") {
                lastProblem = "Python error – see log"
            } else {
                return
            }
        }
        onChange?()
    }

    private func exited(_ p: Process) {
        guard p === process else { return }
        process = nil
        deviceConnected = false
        midiMode = false
        log("Daemon exited (status \(p.terminationStatus))")
        guard wanted else { run = .stopped; onChange?(); return }
        if restartRequested {
            restartRequested = false
            schedule(0.5)
            return
        }
        if Date().timeIntervalSince(startedAt) > 30 { backoff = 1 }
        run = .restarting(in: Int(backoff))
        schedule(backoff)
        backoff = min(backoff * 2, 30)
        onChange?()
    }

    private func fail(_ message: String) {
        log(message)
        lastProblem = message
        run = .stopped
        wanted = false
        onChange?()
    }

    private func schedule(_ delay: TimeInterval) {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.spawn() }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func terminate(_ p: Process) {
        p.terminate()
        let pid = p.processIdentifier
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if p.isRunning { kill(pid, SIGKILL) }
        }
    }
}

// MARK: - Menu helpers

final class ActionItem: NSMenuItem {
    private var handler: () -> Void = {}

    convenience init(_ title: String, key: String = "", enabled: Bool = true, handler: @escaping () -> Void) {
        self.init(title: title, action: #selector(ActionItem.fire), keyEquivalent: key)
        self.handler = handler
        self.target = self
        self.isEnabled = enabled
    }

    @objc private func fire() { handler() }
}

func infoItem(_ title: String) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.isEnabled = false
    return item
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let daemon = DaemonSupervisor()
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0 != NSRunningApplication.current }
        if !others.isEmpty { NSApp.terminate(nil); return }

        log("—— MK1 Bridge started ——")
        killStrayDaemons()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu

        daemon.onChange = { [weak self] in self?.updateIcon() }
        daemon.start()

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            log("Woke from sleep – restarting daemon")
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self?.daemon.restart() }
        }
        updateIcon()
    }

    func applicationWillTerminate(_ notification: Notification) {
        daemon.shutdownNow()
        log("—— MK1 Bridge stopped ——")
    }

    private func killStrayDaemons() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        p.arguments = ["-f", "MK1 Bridge.app/Contents/Resources/daemon/mk1_midi.py"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }

    // MARK: Icon

    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        let symbol: String
        let text: String
        if daemon.run != .running {
            symbol = "exclamationmark.triangle"; text = "Daemon not running"
        } else if !daemon.deviceConnected {
            symbol = "square.grid.3x3"; text = "Maschine not connected"
        } else if daemon.midiMode {
            symbol = "square.grid.3x3.fill"; text = "MIDI mode on"
        } else {
            symbol = "square.grid.3x3.topleft.filled"; text = "Connected, MIDI mode off"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: text)
            ?? NSImage(systemSymbolName: "square.grid.3x3", accessibilityDescription: text)
        image?.isTemplate = true
        button.image = image
        button.toolTip = "MK1 Bridge – \(text)"
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let running = daemon.run == .running

        let daemonText: String
        switch daemon.run {
        case .running: daemonText = "running"
        case .stopped: daemonText = "stopped"
        case .restarting(let s): daemonText = "crashed – restarting in \(s) s"
        }
        menu.addItem(infoItem("Maschine: \(daemon.deviceConnected ? "connected" : "not connected")"))
        menu.addItem(infoItem("Daemon: \(daemonText)"))
        if let problem = daemon.lastProblem {
            menu.addItem(infoItem("⚠︎ \(problem)"))
        }
        menu.addItem(.separator())

        let midiItem = ActionItem("MIDI Mode", key: "m", enabled: running && daemon.deviceConnected) { [weak self] in
            self?.daemon.send(SIGUSR1)
        }
        midiItem.state = daemon.midiMode ? .on : .off
        menu.addItem(midiItem)
        menu.addItem(ActionItem("All Notes Off", enabled: running) { [weak self] in self?.daemon.send(SIGUSR2) })
        menu.addItem(.separator())

        menu.addItem(ActionItem("Edit Configuration…") { Self.openConfig() })
        menu.addItem(ActionItem("Reload Configuration", enabled: running) { [weak self] in
            self?.daemon.send(SIGHUP)
        })
        menu.addItem(ActionItem("Restart Daemon", key: "r") { [weak self] in self?.daemon.restart() })
        menu.addItem(ActionItem("Show Logs") { NSWorkspace.shared.open(Paths.logs) })
        menu.addItem(.separator())

        let login = ActionItem("Start at Login") { [weak self] in self?.toggleLogin() }
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(ActionItem("Quit", key: "q") { NSApp.terminate(nil) })
    }

    // MARK: Actions

    private static func openConfig() {
        guard FileManager.default.fileExists(atPath: Paths.config.path) else {
            alert("No configuration yet",
                  "It is created the first time the daemon starts: \(Paths.config.path)")
            return
        }
        let textEdit = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        NSWorkspace.shared.open([Paths.config], withApplicationAt: textEdit,
                                configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }

    private func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            log("Start at login: \(error.localizedDescription)")
        }
        if service.status == .requiresApproval {
            Self.alert("Approval needed",
                       "Allow MK1 Bridge in System Settings → General → Login Items.")
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    private static func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}

// MARK: - Start

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
