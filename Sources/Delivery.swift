import Foundation

struct LinkRequest: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let sourceID: String?
    let sourceName: String?
    var forceChoice = false

    init(url: URL, sourceID: String?, sourceName: String? = nil) {
        self.id = UUID()
        self.url = url
        self.sourceID = sourceID
        self.sourceName = sourceName
    }
}

struct FailedDelivery: Identifiable, Equatable {
    var id: UUID { request.id }
    let request: LinkRequest
    let message: String
}

/// Only one launch or modal chooser may own a link at a time.
/// Failed URLs stay in memory until successful delivery or explicit dismissal.
final class DeliveryQueue {
    private(set) var pending: [LinkRequest] = []
    private(set) var active: LinkRequest?
    private(set) var failures: [FailedDelivery] = []

    func enqueue(_ request: LinkRequest) {
        guard active?.id != request.id, !pending.contains(where: { $0.id == request.id }) else { return }
        pending.append(request)
    }

    func next() -> LinkRequest? {
        guard active == nil, !pending.isEmpty else { return nil }
        active = pending.removeFirst()
        return active
    }

    func complete(_ id: UUID) {
        guard active?.id == id else { return }
        failures.removeAll { $0.id == id }
        active = nil
    }

    func fail(_ id: UUID, message: String) {
        guard let request = active, request.id == id else { return }
        failures.removeAll { $0.id == id }
        failures.append(FailedDelivery(request: request, message: message))
        active = nil
    }

    func cancel(_ id: UUID) {
        guard active?.id == id else { return }
        active = nil // Cancelling a retry leaves the original failed link available.
    }

    func retry(_ id: UUID, chooseBrowser: Bool) {
        guard var request = failures.first(where: { $0.id == id })?.request else { return }
        request.forceChoice = chooseBrowser
        enqueue(request)
    }

    func dismiss(_ id: UUID) {
        failures.removeAll { $0.id == id }
        pending.removeAll { $0.id == id }
    }
}
