import AppKit
import BridgeCore
import BridgeEngine
import ServiceManagement
import SwiftUI

struct LogLine: Identifiable {
    let id: Int
    let text: String
}

/// Verzamelt logregels van de bridge-thread; de app haalt ze een paar keer per seconde op.
final class LogBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [String] = []

    func append(_ s: String) {
        lock.lock(); pending.append(s); lock.unlock()
    }

    func take() -> [String] {
        lock.lock(); defer { lock.unlock() }
        let p = pending
        pending = []
        return p
    }
}

/// Alles wat de menubalk en het logvenster tonen. Wordt alleen op de main thread gebruikt.
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let engine: BridgeEngine
    private let buffer = LogBuffer()
    private var nextID = 0
    private var logWindow: NSWindow?
    private var mappingWindow: NSWindow?
    private let maxLines = 3000

    @Published var status = EngineStatus()
    @Published var lines: [LogLine] = []
    @Published var startError: String?
    @Published var savedMessage: String?
    @Published var launchAtLogin = false

    private init() {
        var options = EngineOptions()
        options.echoLog = false
        engine = BridgeEngine(options: options)

        let buffer = self.buffer
        engine.log.onLine = { line in buffer.append(line) }
        engine.onStatus = { [weak self] st in
            DispatchQueue.main.async { self?.apply(st) }
        }
        engine.onQuitRequested = {
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.flushLog()
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: Bridge

    func start() {
        startError = nil
        do {
            try engine.start()
        } catch {
            startError = error.localizedDescription
        }
    }

    func shutdown() {
        engine.shutdown()
    }

    private func apply(_ st: EngineStatus) {
        if let saved = st.lastSaved, saved != status.lastSaved {
            savedMessage = st.lastSaveMessage ?? tr("Saved", "Opgeslagen")
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self, self.status.lastSaved == saved else { return }
                self.savedMessage = nil
            }
        }
        status = st
    }

    var bcfConnected: Bool { status.bcfIn != nil && status.bcfOut != nil }

    var menuIcon: String {
        if startError != nil || !bcfConnected { return "exclamationmark.triangle" }
        return status.logicOnline ? "slider.vertical.3" : "slider.horizontal.3"
    }

    // MARK: Instellingen

    func setTopRow(_ f: ButtonFunction) { engine.setRowFunction(top: true, f) }
    func setBottomRow(_ f: ButtonFunction) { engine.setRowFunction(top: false, f) }
    func setReleaseMs(_ ms: Int) { engine.setReleaseMs(ms) }

    func confirmReset() {
        let alert = NSAlert()
        alert.messageText = tr("Reset the mapping to the default?", "Mapping terugzetten naar de standaard?")
        alert.informativeText = tr("The current mapping is kept as \(BridgeSettings.backup.lastPathComponent).", "De huidige mapping wordt bewaard als \(BridgeSettings.backup.lastPathComponent).")
        alert.addButton(withTitle: tr("Reset", "Terugzetten"))
        alert.addButton(withTitle: tr("Cancel", "Annuleren"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { engine.resetMapping() }
    }

    func exportMapping() {
        let panel = NSSavePanel()
        panel.title = tr("Export mapping", "Mapping exporteren")
        panel.nameFieldStringValue = "BCF Bridge mapping.json"
        panel.allowedContentTypes = [.json]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        engine.exportMapping(to: url) { error in
            DispatchQueue.main.async {
                if let error { Self.showError(tr("Export failed", "Exporteren mislukt"), error) }
            }
        }
    }

    func importMapping() {
        let panel = NSOpenPanel()
        panel.title = tr("Import mapping", "Mapping importeren")
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        engine.importMapping(from: url) { error in
            DispatchQueue.main.async {
                if let error { Self.showError(tr("Import failed", "Importeren mislukt"), error) }
            }
        }
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            Self.showError(tr("Could not set launch at login", "Starten bij inloggen lukt niet"), error)
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    static func showError(_ title: String, _ error: Error) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: Log

    private func flushLog() {
        let new = buffer.take()
        guard !new.isEmpty else { return }
        var all = lines
        for s in new {
            all.append(LogLine(id: nextID, text: s))
            nextID += 1
        }
        if all.count > maxLines { all.removeFirst(all.count - maxLines) }
        lines = all
    }

    func copyLog() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.map(\.text).joined(separator: "\n"), forType: .string)
    }

    func revealLogFile() {
        NSWorkspace.shared.activateFileViewerSelecting([engine.log.fileURL])
    }

    func showLogWindow() {
        if logWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 560),
                             styleMask: [.titled, .closable, .resizable, .miniaturizable],
                             backing: .buffered, defer: false)
            w.title = "BCF Bridge log"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: LogView().environmentObject(self))
            w.center()
            logWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        logWindow?.makeKeyAndOrderFront(nil)
    }

    func showMappingWindow() {
        if mappingWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
                             styleMask: [.titled, .closable, .resizable, .miniaturizable],
                             backing: .buffered, defer: false)
            w.title = "BCF Bridge mapping"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: MappingView().environmentObject(self))
            w.center()
            mappingWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        mappingWindow?.makeKeyAndOrderFront(nil)
    }
}
