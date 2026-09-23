import Foundation

@MainActor
public final class SmartCorrection {
    public nonisolated static let maximumAddedWait: Duration = .milliseconds(350)
    public nonisolated static let maximumRevisionWait: Duration = .seconds(1)
    private let service: any TranscriptCorrecting
    private let context: CorrectionContext
    private let debounce: Duration
    private let finalWait: Duration
    private let revisionWait: Duration
    private let maximumPreviews: Int
    private var previewCount = 0
    private var latest = ""
    private var debounceTask: Task<Void, Never>?
    private var pending: (source: String, task: Task<String, Never>)?
    private var cached: (source: String, result: String)?
    private var continuation: AsyncStream<String>.Continuation?
    private var finishing = false
    private var cancelled = false

    public init(
        service: any TranscriptCorrecting,
        context: CorrectionContext = CorrectionContext(),
        debounce: Duration = .milliseconds(300),
        finalWait: Duration = SmartCorrection.maximumAddedWait,
        revisionWait: Duration = SmartCorrection.maximumRevisionWait,
        maximumPreviews: Int = 4
    ) {
        self.service = service
        self.context = context
        self.debounce = debounce
        self.finalWait = finalWait
        self.revisionWait = revisionWait
        self.maximumPreviews = maximumPreviews
    }

    public func preview(_ text: String) {
        guard !cancelled, !finishing, text != latest else { return }
        latest = text
        debounceTask?.cancel()
        guard CorrectionPolicy.isEligible(text), previewCount < maximumPreviews else { return }
        debounceTask = Task { [weak self, debounce] in
            do { try await Task.sleep(for: debounce) } catch { return }
            guard let self, !self.cancelled, !self.finishing, self.latest == text else { return }
            self.prepareLatest()
        }
    }

    public func prepareLatest() {
        guard !cancelled, !finishing, CorrectionPolicy.isEligible(latest), previewCount < maximumPreviews,
              pending?.source != latest, cached?.source != latest else { return }
        debounceTask?.cancel()
        previewCount += 1
        _ = begin(latest)
    }

    public func finish(_ text: String) async -> String {
        guard !cancelled, !finishing else { return text }
        finishing = true
        debounceTask?.cancel()
        defer { cancel() }
        guard CorrectionPolicy.isEligible(text), !Task.isCancelled else { return text }
        if let cached, cached.source == text { return cached.result }
        let work = pending?.source == text ? pending!.task : begin(text)
        let pair = AsyncStream<String>.makeStream(bufferingPolicy: .bufferingOldest(1))
        continuation = pair.continuation
        let response = Task {
            let result = await work.value
            guard !Task.isCancelled else { return }
            pair.continuation.yield(result)
            pair.continuation.finish()
        }
        let wait = CorrectionPolicy.revisesItself(text) ? max(finalWait, revisionWait) : finalWait
        let deadline = Task {
            do { try await Task.sleep(for: wait) } catch { return }
            pair.continuation.yield(text)
            pair.continuation.finish()
            work.cancel()
        }
        defer {
            response.cancel()
            deadline.cancel()
            pair.continuation.finish()
        }
        for await result in pair.stream { return result }
        return text
    }

    public func cancel() {
        cancelled = true
        debounceTask?.cancel()
        pending?.task.cancel()
        pending = nil
        cached = nil
        continuation?.finish()
        continuation = nil
    }

    private func begin(_ text: String) -> Task<String, Never> {
        pending?.task.cancel()
        let work = Task { [weak self, service, context] in
            let result: String
            do {
                let candidate = try await service.correct(text, context: context)
                result = CorrectionPolicy.accept(text, candidate: candidate, keywords: context.keywords) ?? text
            } catch { return text }
            guard !Task.isCancelled, let self, !self.cancelled else { return text }
            self.cached = (text, result)
            return result
        }
        pending = (text, work)
        return work
    }
}
