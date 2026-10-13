import Combine
import Foundation

/// Temporary automatic-check pauses are per app and never modify saved rules.
/// A single timer wakes at the nearest deadline, including in menu tracking mode.
final class AppPauseStore: ObservableObject {
    @Published private(set) var deadlines: [String: Date] = [:]
    var onChange: (Set<String>) -> Void = { _ in }
    private let now: () -> Date
    private let automaticallyExpires: Bool
    private var timer: Timer?

    init(now: @escaping () -> Date = Date.init, automaticallyExpires: Bool = true) {
        self.now = now
        self.automaticallyExpires = automaticallyExpires
    }

    deinit { timer?.invalidate() }

    func deadline(for bundleId: String) -> Date? {
        guard let deadline = deadlines[bundleId], deadline > now() else { return nil }
        return deadline
    }

    func permitsAutomaticCheck(_ bundleId: String, enabled: Bool) -> Bool {
        enabled && deadline(for: bundleId) == nil
    }

    func pause(_ bundleId: String, for duration: TimeInterval = 15 * 60) {
        guard !bundleId.isEmpty, duration.isFinite, duration > 0 else { return }
        deadlines[bundleId] = now().addingTimeInterval(duration)
        scheduleExpiration()
        onChange([bundleId])
    }

    func resume(_ bundleId: String) {
        guard deadlines.removeValue(forKey: bundleId) != nil else { return }
        scheduleExpiration()
        onChange([bundleId])
    }

    func refreshExpirations() {
        let date = now()
        let expired = Set(deadlines.filter { $0.value <= date }.map(\.key))
        if !expired.isEmpty {
            deadlines = deadlines.filter { !expired.contains($0.key) }
        }
        scheduleExpiration()
        if !expired.isEmpty { onChange(expired) }
    }

    private func scheduleExpiration() {
        timer?.invalidate()
        timer = nil
        guard automaticallyExpires, let next = deadlines.values.min() else { return }
        let timer = Timer(timeInterval: max(0.01, next.timeIntervalSince(now())), repeats: false) {
            [weak self] _ in self?.refreshExpirations()
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
}
