import AppKit
import Combine
import SwiftUI

@main
struct SpeakApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        if CommandLine.arguments.contains("--render-previews") {
            PreviewRenderer.render()
            return
        }
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var window: NSWindow?
    private var pill: PillController?
    private var status: NSStatusItem?
    private var subscriptions = Set<AnyCancellable>()
    private var recordItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installApplicationMenu()
        installStatusItem()
        model.showWindow = { [weak self] in self?.openWindow() }
        model.launch()
        pill = PillController(model: model)
        if !CommandLine.arguments.contains("--background") { openWindow() }
        model.$phase.sink { [weak self] phase in
            self?.recordItem?.title = phase.isRecording ? "Finish dictation" : "Start dictation"
            self?.status?.button?.contentTintColor = phase.isBusy ? NSColor.systemOrange : nil
        }.store(in: &subscriptions)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openWindow()
        return true
    }
    func applicationWillTerminate(_ notification: Notification) { model.shutdown() }

    @objc private func openWindow() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 640), styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "Speak"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.backgroundColor = NSColor(Color.canvas)
            window.contentView = NSHostingView(rootView: MainView(model: model))
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleDictation() { model.toggle() }
    @objc private func pasteLast() { model.pasteLast() }
    @objc private func copyLast() { model.copyLast() }
    @objc private func openPreferences() { model.selectedTab = 1; openWindow() }
    @objc private func quit() { NSApp.terminate(nil) }

    private func installStatusItem() {
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = BrandMark.menuBarImage()
        status.button?.image = image
        status.button?.toolTip = "Speak · Hold \(model.preferences.shortcutLabel) to dictate"
        let menu = NSMenu()
        add("Open Speak", action: #selector(openWindow), to: menu)
        menu.addItem(.separator())
        recordItem = add("Start dictation", action: #selector(toggleDictation), to: menu)
        add("Paste last dictation", action: #selector(pasteLast), to: menu)
        add("Copy last dictation", action: #selector(copyLast), to: menu)
        menu.addItem(.separator())
        add("Preferences…", action: #selector(openPreferences), to: menu)
        add("Quit Speak", action: #selector(quit), to: menu)
        status.menu = menu
        self.status = status
    }

    @discardableResult private func add(_ title: String, action: Selector, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    private func installApplicationMenu() {
        let root = NSMenu()
        let appMenu = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        root.addItem(appItem)
        appMenu.addItem(withTitle: "Quit Speak", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editMenu = NSMenu(title: "Edit")
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = editMenu
        root.addItem(editItem)
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        NSApp.mainMenu = root
    }
}

@MainActor
enum PreviewRenderer {
    static func render() {
        guard let index = CommandLine.arguments.firstIndex(of: "--render-previews"),
              CommandLine.arguments.count > index + 1 else { return }
        let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1])
        let defaults = UserDefaults(suiteName: "local.speak.preview")!
        let preferences = Preferences(defaults: defaults)
        preferences.hasAPIKey = false
        let model = AppModel(preferences: preferences)
        save(MainView(model: model), to: directory.appendingPathComponent("setup.png"))
        model.selectedTab = 1
        save(MainView(model: model), to: directory.appendingPathComponent("preferences.png"))
        model.selectedTab = 0
        preferences.hasAPIKey = true
        model.microphoneGranted = true
        model.accessibilityGranted = true
        model.shortcutAvailable = true
        save(MainView(model: model), to: directory.appendingPathComponent("ready.png"))
        model.phase = .listening
        model.level = 0.65
        model.elapsed = 8
        model.partial = "Let’s keep this simple. A small app that turns your thoughts into words."
        save(PillView(model: model).frame(width: 430, height: 190), to: directory.appendingPathComponent("recording.png"))
    }

    private static func save<V: View>(_ view: V, to url: URL) {
        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        hosting.layoutSubtreeIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        do { try bitmap.representation(using: .png, properties: [:])?.write(to: url) }
        catch { fputs("Could not render preview: \(error.localizedDescription)\n", stderr) }
        window.close()
    }
}
