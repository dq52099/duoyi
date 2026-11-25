import Foundation

// One immutable projection of one validated canonical read. Preferences can
// contribute only device-owned display density, never account/presentation data.
struct DuoyiWidgetPublicationCapture {
    // Bounded retry policy for transient store contention (e.g. active write transaction).
    static let defaultMaxBusyRetries = 2
    static let defaultBusyRetryDelay: TimeInterval = 0.025

    // When transient store contention outlasts immediate retries, ask
    // WidgetKit for an early reload rather than waiting the full 15 minutes.
    static let busyReloadIntervalSeconds: TimeInterval = 30

    let status: String
    let values: [String: Any]

    var isBusy: Bool { status == "busy" }
    var isReadyOrSealed: Bool { status == "ready" || status == "sealed" }

    init(read: DuoyiWidgetPublicationRead, displayMode: Any?) {
        self.status = read.status
        var captured: [String: Any] = [:]
        if let envelope = read.envelope, read.status == (envelope.active ? "ready" : "sealed") {
            captured = envelope.document.toFlatValues
        }
        let mode = displayMode as? String
        captured["widget_display_mode"] = ["compact", "standard", "detailed"].contains(mode ?? "") ? mode! : "standard"
        self.values = captured
    }

    static func capture(
        read: () -> DuoyiWidgetPublicationRead,
        displayMode: () -> Any?,
        maxBusyRetries: Int = defaultMaxBusyRetries,
        retryDelay: TimeInterval = defaultBusyRetryDelay,
        sleep: (TimeInterval) -> Void = { if $0 > 0 { Thread.sleep(forTimeInterval: $0) } }
    ) -> Self {
        var publication = read()
        var retriesLeft = max(0, maxBusyRetries)
        while publication.status == "busy" && retriesLeft > 0 {
            retriesLeft -= 1
            sleep(retryDelay)
            publication = read()
        }
        return Self(read: publication, displayMode: displayMode())
    }

    func timelineRefreshDate(
        now: Date,
        focusTimerRunning: Bool,
        nextTransition: Date? = nil
    ) -> Date {
        Self.timelineRefreshDate(
            now: now,
            focusTimerRunning: focusTimerRunning,
            nextTransition: nextTransition,
            isBusy: isBusy
        )
    }

    static func timelineRefreshDate(
        now: Date,
        focusTimerRunning: Bool,
        nextTransition: Date? = nil,
        isBusy: Bool
    ) -> Date {
        let refreshMinutes = focusTimerRunning ? 1 : 15
        var nextRefresh = now.addingTimeInterval(TimeInterval(refreshMinutes * 60))
        if let nextTransition = nextTransition {
            nextRefresh = min(nextRefresh, nextTransition)
        }
        if isBusy {
            nextRefresh = min(nextRefresh, now.addingTimeInterval(busyReloadIntervalSeconds))
        }
        return nextRefresh
    }
}
