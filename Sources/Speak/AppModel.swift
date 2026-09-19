import AppKit
import AVFoundation
import Combine
import SpeakCore

@MainActor
final class AppModel: ObservableObject {
    enum Phase: Equatable {
        case idle, connecting, listening, finishing, success, failure
        var isRecording: Bool { self == .connecting || self == .listening }
        var isBusy: Bool { isRecording || self == .finishing }
    }

    let preferences: Preferences
    let shortcut = GlobalShortcut()
    let insertion: TextInsertion
    private let captureTarget: () -> InsertionTarget?
    @Published var phase: Phase = .idle
    @Published var partial = ""
    @Published var lastTranscript = ""
    @Published var message = ""
    @Published var level: Float = 0
    @Published var elapsed: TimeInterval = 0
    @Published var lastLatency: Int?
    @Published var handsFree = false
    @Published var microphoneGranted = false
    @Published var accessibilityGranted = false
    @Published var shortcutAvailable = false
    @Published var selectedTab = 0
    var showWindow: (() -> Void)?
    private var capture: AudioCapture?
    private var transcriber: RealtimeTranscriber?
    private var task: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?
    private var permissionTimer: Timer?
    private var subscriptions = Set<AnyCancellable>()
    private var takeID = UUID()
    private var startedAt = Date()
    private var releasedAt: Date?
    private var target: InsertionTarget?

    init(
        preferences: Preferences? = nil,
        insertion: TextInsertion? = nil,
        captureTarget: (() -> InsertionTarget?)? = nil
    ) {
        let preferences = preferences ?? Preferences()
        self.preferences = preferences
        self.insertion = insertion ?? TextInsertion()
        self.captureTarget = captureTarget ?? InsertionTarget.capture
        shortcut.isActive = { [weak self] in self?.phase.isBusy ?? false }
        shortcut.onCancel = { [weak self] in self?.cancel() }
        shortcut.onPaste = { [weak self] in self?.pasteLast() }
        shortcut.onCopy = { [weak self] in self?.copyLast() }
        shortcut.onAction = { [weak self] action in
            guard let self else { return }
            switch action {
            case .startHold: self.start(handsFree: false)
            case .startHandsFree: self.start(handsFree: true)
            case .lock: self.handsFree = true
            case .finish: self.finish()
            case .cancel: self.cancel(resetShortcut: false)
            }
        }
        preferences.$shortcut.sink { [weak self] value in
            self?.shortcut.usesFunctionKey = value == "fn"
            self?.shortcut.reset()
        }.store(in: &subscriptions)
        preferences.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
    }

    var ready: Bool { preferences.hasAPIKey && microphoneGranted && accessibilityGranted && shortcutAvailable }
    var timeLabel: String { String(format: "%d:%02d", Int(elapsed) / 60, Int(elapsed) % 60) }
    var phaseLabel: String {
        switch phase {
        case .idle: return ready ? "Ready when you are" : "A little setup. Then just speak."
        case .connecting: return "Listening · connecting"
        case .listening: return "Listening"
        case .finishing: return "Finishing your thought"
        case .success: return message
        case .failure: return "Something needs your attention"
        }
    }

    func launch() {
        refreshPermissions()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshPermissions() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.cancel() }
        }
    }

    func refreshPermissions() {
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibilityGranted = AXIsProcessTrusted()
        if accessibilityGranted {
            shortcutAvailable = shortcut.install()
        } else {
            shortcut.stop()
            shortcutAvailable = false
        }
    }

    func requestMicrophone() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .notDetermined {
            Task {
                _ = await AVCaptureDevice.requestAccess(for: .audio)
                refreshPermissions()
            }
        } else if status != .authorized {
            openPrivacy("Microphone")
        }
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        if !AXIsProcessTrusted() { openPrivacy("Accessibility") }
        refreshPermissions()
    }

    func openPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    func start(handsFree: Bool) {
        guard !phase.isBusy else { return }
        refreshPermissions()
        guard ready else {
            selectedTab = 1
            showWindow?()
            return
        }
        let target = captureTarget()
        guard target?.isSecure != true else {
            fail("For your privacy, dictation is disabled in password fields.")
            return
        }
        dismissTask?.cancel()
        takeID = UUID()
        let id = takeID
        self.target = target
        self.handsFree = handsFree
        if handsFree { shortcut.enterHandsFree() }
        partial = ""
        message = ""
        level = 0
        elapsed = 0
        releasedAt = nil
        startedAt = Date()
        phase = .connecting
        do {
            let key = try KeychainStore.read()
            let capture = AudioCapture()
            let audio = try capture.start { [weak self] level in
                Task { @MainActor in
                    guard self?.takeID == id, self?.phase.isRecording == true else { return }
                    self?.level = level
                }
            }
            self.capture = capture
            let transcriber = RealtimeTranscriber(socket: OpenAIWebSocket(apiKey: key))
            self.transcriber = transcriber
            let configuration = preferences.configuration
            timer = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                    guard let self, self.takeID == id, self.phase.isRecording else { return }
                    self.elapsed = Date().timeIntervalSince(self.startedAt)
                    if self.elapsed >= 300 { self.finish(); return }
                }
            }
            task = Task { [weak self] in
                do {
                    let final = try await transcriber.transcribe(audio: audio, configuration: configuration) { [weak self] in
                        guard let self, self.takeID == id else { return }
                        if self.phase == .connecting { self.phase = .listening }
                    } onPartial: { [weak self] text in
                        guard self?.takeID == id else { return }
                        self?.partial = text
                    }
                    guard let self, self.takeID == id, !Task.isCancelled else { return }
                    self.complete(final)
                } catch is CancellationError {
                } catch {
                    guard let self, self.takeID == id else { return }
                    self.fail(error.localizedDescription)
                }
            }
        } catch { fail(error.localizedDescription) }
    }

    func finish() {
        guard phase.isRecording else { return }
        shortcut.reset()
        target = captureTarget() ?? target
        releasedAt = Date()
        elapsed = Date().timeIntervalSince(startedAt)
        phase = .finishing
        level = 0
        timer?.cancel()
        transcriber?.finishSoon()
        capture?.stop()
        capture = nil
    }

    func cancel(resetShortcut: Bool = true) {
        if resetShortcut { shortcut.reset() }
        guard phase.isBusy else { return }
        takeID = UUID()
        capture?.stop()
        capture = nil
        transcriber?.cancel()
        transcriber = nil
        task?.cancel()
        timer?.cancel()
        partial = ""
        level = 0
        phase = .idle
    }

    func toggle() {
        if phase.isRecording { finish() }
        else if !phase.isBusy { start(handsFree: true) }
    }

    func copyLast() {
        guard !lastTranscript.isEmpty else { return }
        insertion.copy(lastTranscript)
        if !phase.isBusy { message = "Copied to clipboard"; phase = .success; dismissLater() }
    }

    func pasteLast() {
        guard !lastTranscript.isEmpty, !phase.isBusy else { return }
        let target = captureTarget()
        guard target?.isSecure != true else { return }
        let result = insertion.insert(lastTranscript, into: target)
        message = result == .pasted ? "Sent to \(target?.name ?? "your app")" : "Copied · press ⌘V to paste"
        phase = .success
        dismissLater()
    }

    func dismiss() { if !phase.isBusy { phase = .idle; message = "" } }

    func shutdown() {
        cancel()
        shortcut.stop()
        permissionTimer?.invalidate()
        insertion.restoreClipboard()
    }

    func complete(_ text: String) {
        guard phase == .finishing else { return }
        capture?.stop()
        capture = nil
        timer?.cancel()
        transcriber = nil
        partial = ""
        if let releasedAt { lastLatency = Int(Date().timeIntervalSince(releasedAt) * 1000) }
        let result = insertion.insert(text, into: target)
        lastTranscript = text
        message = result == .pasted ? "Sent to \(target?.name ?? "your app")" : "Copied · press ⌘V to paste"
        phase = .success
        dismissLater()
    }

    private func fail(_ text: String) {
        capture?.stop()
        capture = nil
        transcriber?.cancel()
        transcriber = nil
        timer?.cancel()
        shortcut.reset()
        level = 0
        message = text
        phase = .failure
    }

    private func dismissLater() {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            self?.dismiss()
        }
    }
}
