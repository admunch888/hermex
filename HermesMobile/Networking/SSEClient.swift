import Foundation
import LDSwiftEventSource
import OSLog

@MainActor
final class SSEClient: SSEStreamingClient {
    private let baseConfiguration: URLSessionConfiguration
    private var eventSource: EventSource?
    private(set) var lastEventID: String?
    /// Read at stream start so a new stream picks up the latest headers (#255).
    private let customHeaderProvider: @MainActor () -> [CustomHeader]

    init(
        urlSessionConfiguration: URLSessionConfiguration = .default,
        customHeaderProvider: @escaping @MainActor () -> [CustomHeader] = { CustomHeaderStore.shared.snapshot() }
    ) {
        baseConfiguration = urlSessionConfiguration
        self.customHeaderProvider = customHeaderProvider
    }

    func start(url: URL, onEvent: @escaping @MainActor (SSEEvent) -> Void) {
        stop()
        lastEventID = nil

        let handler = SSEEventHandler(
            onEventID: { [weak self] eventID in
                self?.lastEventID = eventID
            },
            onEvent: onEvent
        )
        var config = EventSource.Config(handler: handler, url: url)
        config.connectionErrorHandler = { _ in .shutdown }
        // Custom headers merged underneath the built-ins so the built-ins win on
        // collision; an empty list leaves the built-in three unchanged (#255).
        config.headers = customHeaderProvider().merged(under: [
            "Accept": "text/event-stream",
            "Cache-Control": "no-cache, no-transform",
            "Accept-Encoding": "identity"
        ])

        let configuration = baseConfiguration.copy() as? URLSessionConfiguration ?? .default
        configuration.httpCookieStorage = .shared
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.urlSessionConfiguration = configuration

        let source = EventSource(config: config)
        eventSource = source
        source.start()
    }

    func stop() {
        eventSource?.stop()
        eventSource = nil
    }
}
private final class SSEEventHandler: EventHandler {
    private let onEventID: @MainActor (String) -> Void
    private let onEvent: @MainActor (SSEEvent) -> Void

    init(
        onEventID: @escaping @MainActor (String) -> Void,
        onEvent: @escaping @MainActor (SSEEvent) -> Void
    ) {
        self.onEventID = onEventID
        self.onEvent = onEvent
    }

    func onOpened() {}

    func onClosed() {}

    func onMessage(eventType: String, messageEvent: MessageEvent) {
        let event = SSEEventDecoder.decode(eventType: eventType, data: messageEvent.data)

        Task { @MainActor in
            let eventID = messageEvent.lastEventId.trimmingCharacters(in: .whitespacesAndNewlines)
            if !eventID.isEmpty {
                onEventID(eventID)
            }
            onEvent(event)
        }
    }

    func onComment(comment _: String) {
        Task { @MainActor in
            onEvent(.heartbeat)
        }
    }

    func onError(error: Error) {
        Task { @MainActor in
            onEvent(.transportError(error.localizedDescription))
        }
    }
}
