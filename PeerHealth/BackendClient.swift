//
//  BackendClient.swift
//  PeerHealth
//
//  Replaces TCPConnectionManager. Speaks the GX10 backend protocol:
//    - WebSocket  ws://<host>:<port>/ws        (connect handshake + event stream + ask)
//    - HTTP POST  http://<host>:<port>/api/sync (health data ingestion)
//
//  Defaults are hardcoded for the hackathon GX10 box, but host/port/user can
//  be overridden in settings.
//

import Combine
import Foundation

@MainActor
final class BackendClient: NSObject, ObservableObject {

    // MARK: Tunables

    static let defaultHost = "100.75.187.58"
    static let defaultPort = "8000"
    static let defaultUserID = "user_1"

    // MARK: Configuration (persisted)

    @Published var host: String {
        didSet { UserDefaults.standard.set(host, forKey: "peerHealthHost") }
    }
    @Published var port: String {
        didSet { UserDefaults.standard.set(port, forKey: "peerHealthPort") }
    }
    @Published var userID: String {
        didSet { UserDefaults.standard.set(userID, forKey: "peerHealthUserID") }
    }

    // MARK: Connection state

    @Published private(set) var isConnected = false
    @Published private(set) var statusText = "Disconnected"

    // MARK: Event stream

    @Published private(set) var feed: [BackendEvent] = []
    @Published private(set) var latestSynthesis: String?
    @Published private(set) var latestNoAnomalySummary: String?
    /// Accumulating chat answer (chat_token stream) for the current ask.
    @Published private(set) var streamingChat: String = ""
    @Published private(set) var isChatStreaming: Bool = false

    /// True between the first orchestration signal (agent_step / tool_call /
    /// shout_published / peer_active / peer_reply / agent_text) and the next
    /// terminal event (synthesis / no_anomaly).
    @Published private(set) var isThinking: Bool = false
    /// The human-friendly current phase label, e.g. "Analyzing your biometrics".
    @Published private(set) var currentPhase: String?

    /// Peers participating in the current/last orchestration run, keyed by
    /// their backend `peer_label`.
    @Published private(set) var peers: [PeerNode] = []
    /// Bumped whenever a `shout_published` event fires; the network graph
    /// observes this to re-trigger its outgoing pulse animation.
    @Published private(set) var shoutPulseToken: Int = 0
    /// Recent peer-to-you exchanges shown under the network graph.
    @Published private(set) var exchanges: [PeerExchange] = []

    // MARK: Internals

    private var webSocket: URLSessionWebSocketTask?
    private lazy var urlSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.waitsForConnectivity = true
        cfg.timeoutIntervalForRequest = 30
        return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }()
    private var receiveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempt = 0
    private var manuallyDisconnected = false
    /// Increments on every openSocket; lets stale callbacks ignore themselves.
    private var generation: Int = 0

    // MARK: Init

    override init() {
        let storedHost = UserDefaults.standard.string(forKey: "peerHealthHost")
        self.host = (storedHost?.isEmpty == false) ? storedHost! : Self.defaultHost
        let storedPort = UserDefaults.standard.string(forKey: "peerHealthPort")
        self.port = (storedPort?.isEmpty == false) ? storedPort! : Self.defaultPort
        let storedUser = UserDefaults.standard.string(forKey: "peerHealthUserID")
        self.userID = (storedUser?.isEmpty == false) ? storedUser! : Self.defaultUserID
        super.init()
    }

    // MARK: Public lifecycle

    func connect() {
        manuallyDisconnected = false
        reconnectAttempt = 0
        openSocket()
    }

    /// Re-pulls host/port/user from UserDefaults — call before connect() if
    /// another part of the UI (like onboarding) may have written values after
    /// this instance was created.
    func refreshFromDefaults() {
        if let stored = UserDefaults.standard.string(forKey: "peerHealthHost"),
           !stored.isEmpty, stored != host { host = stored }
        if let stored = UserDefaults.standard.string(forKey: "peerHealthPort"),
           !stored.isEmpty, stored != port { port = stored }
        if let stored = UserDefaults.standard.string(forKey: "peerHealthUserID"),
           !stored.isEmpty, stored != userID { userID = stored }
    }

    func disconnect() {
        manuallyDisconnected = true
        cancelReconnect()
        closeSocket()
        isConnected = false
        statusText = "Disconnected"
    }

    /// Called from scenePhase observers when the app comes to foreground.
    func ensureConnected() {
        guard !manuallyDisconnected else { return }
        if !isConnected && webSocket == nil {
            openSocket()
        }
    }

    /// Called when host/port/userID changes from settings UI.
    func reconnectFromSettings() {
        cancelReconnect()
        closeSocket()
        connect()
    }

    // MARK: Outbound — chat ask

    func sendAsk(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        streamingChat = ""
        isChatStreaming = true
        sendJSON(["type": "ask", "user_id": userID, "text": trimmed])
    }

    /// User-initiated full pipeline run. Resets prior peer/synthesis state so
    /// the Network screen animates the new run from scratch, then sends an
    /// `ask` with a canned prompt that exercises analyzer+radar+synthesizer.
    func analyze() {
        peers = []
        exchanges = []
        latestSynthesis = nil
        latestNoAnomalySummary = nil
        currentPhase = nil
        isThinking = false
        sendAsk("Run a fresh analysis on my latest biometrics, talk to your peers, and tell me what you find.")
    }

    // MARK: Outbound — HTTP /api/sync

    /// Posts a samples bundle (already in aggregator-shape) to the backend.
    /// Returns true on 2xx.
    @discardableResult
    func pushHealthData(samples: [String: Any]) async -> Bool {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPort = port.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !trimmedHost.isEmpty,
            !trimmedPort.isEmpty,
            let url = URL(string: "http://\(trimmedHost):\(trimmedPort)/api/sync")
        else {
            statusText = "Invalid sync URL"
            return false
        }

        let body: [String: Any] = [
            "user_id": userID,
            "samples": samples
        ]

        guard let payload = try? JSONSerialization.data(withJSONObject: body) else {
            statusText = "Health bundle encode failed"
            return false
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = payload

        do {
            let (_, response) = try await urlSession.data(for: req)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                statusText = "Sync HTTP \(http.statusCode)"
                return false
            }
            statusText = "Synced /api/sync at \(Self.shortTimeFormatter.string(from: Date()))"
            return true
        } catch {
            statusText = "Sync failed: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: Internal — open / close

    private func openSocket() {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPort = port.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !trimmedHost.isEmpty,
            !trimmedPort.isEmpty,
            let url = URL(string: "ws://\(trimmedHost):\(trimmedPort)/ws")
        else {
            statusText = "Invalid host/port"
            return
        }

        closeSocket()

        generation += 1
        let myGen = generation
        statusText = "Connecting to \(trimmedHost):\(trimmedPort)/ws…"

        let task = urlSession.webSocketTask(with: url)
        webSocket = task
        task.resume()

        receiveTask = Task { [weak self] in
            await self?.receiveLoop(generation: myGen)
        }
    }

    private func closeSocket() {
        receiveTask?.cancel()
        receiveTask = nil
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
    }

    private func cancelReconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
    }

    // MARK: Internal — send

    private func sendJSON(_ dict: [String: Any]) {
        guard let socket = webSocket else {
            statusText = "Not connected"
            return
        }
        guard
            let data = try? JSONSerialization.data(withJSONObject: dict),
            let str = String(data: data, encoding: .utf8)
        else {
            return
        }
        socket.send(.string(str)) { [weak self] error in
            guard let self else { return }
            if let error {
                Task { @MainActor in
                    self.statusText = "Send failed: \(error.localizedDescription)"
                    self.handleDisconnect()
                }
            }
        }
    }

    // MARK: Internal — receive loop

    private func receiveLoop(generation: Int) async {
        while !Task.isCancelled, generation == self.generation, let socket = webSocket {
            do {
                let message = try await socket.receive()
                await MainActor.run {
                    guard generation == self.generation else { return }
                    self.handleIncoming(message)
                }
            } catch {
                await MainActor.run {
                    guard generation == self.generation else { return }
                    self.statusText = "Receive failed: \(error.localizedDescription)"
                    self.handleDisconnect()
                }
                return
            }
        }
    }

    private func handleIncoming(_ message: URLSessionWebSocketTask.Message) {
        let text: String?
        switch message {
        case .string(let s): text = s
        case .data(let d):   text = String(data: d, encoding: .utf8)
        @unknown default:    text = nil
        }
        guard let text else { return }

        guard
            let data = text.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let typeStr = json["type"] as? String
        else {
            appendEvent(.init(timestamp: Date(), kind: .system, label: text))
            return
        }

        switch typeStr {
        case "agent_step":
            let raw = (json["label"] as? String) ?? ""
            let phase = Self.phaseDisplay(raw)
            currentPhase = phase
            isThinking = true
            appendEvent(.init(timestamp: Date(), kind: .agentStep, label: phase))

        case "tool_call", "tool_result":
            // Internal model↔tool plumbing — don't surface to the user.
            isThinking = true
            return

        case "shout_published":
            currentPhase = "Communicating on the network"
            isThinking = true
            shoutPulseToken &+= 1
            appendEvent(.init(timestamp: Date(), kind: .shoutPublished,
                              label: "checking for similar cases"))

        case "peer_active":
            let lbl = (json["peer_label"] as? String) ?? "peer"
            currentPhase = "Listening for peer wisdom"
            isThinking = true
            upsertPeer(label: lbl, state: .pending)
            recordExchange(peer: lbl, status: .pending)
            appendEvent(.init(timestamp: Date(), kind: .peerActive,
                              label: "\(Self.prettyPeer(lbl)) is thinking it over"))

        case "peer_reply":
            let lbl = (json["peer_label"] as? String) ?? "peer"
            isThinking = true
            upsertPeer(label: lbl, state: .replied)
            recordExchange(peer: lbl, status: .replied)
            appendEvent(.init(timestamp: Date(), kind: .peerReply,
                              label: "heard back from \(Self.prettyPeer(lbl))"))

        case "agent_text":
            // Intermediate model thoughts are noise — the synthesis frame is
            // the canonical user-facing answer. Just stay in the thinking state.
            let agent = (json["agent"] as? String) ?? ""
            if agent.hasPrefix("synthesizer_") { return }
            isThinking = true
            return

        case "no_anomaly":
            let summary = Self.maskUserIDs((json["summary"] as? String) ?? "")
            latestNoAnomalySummary = summary
            isThinking = false
            currentPhase = nil
            appendEvent(.init(timestamp: Date(), kind: .noAnomaly, label: summary))

        case "synthesis":
            let txt = Self.maskUserIDs((json["text"] as? String) ?? "")
            latestSynthesis = txt
            isChatStreaming = false
            isThinking = false
            currentPhase = nil
            appendEvent(.init(timestamp: Date(), kind: .synthesis, label: txt))

        case "chat_token":
            let txt = (json["text"] as? String) ?? ""
            streamingChat += txt
            isChatStreaming = true

        default:
            appendEvent(.init(timestamp: Date(), kind: .system, label: "[\(typeStr)] \(text)"))
        }
    }

    // MARK: - Label helpers

    /// Replaces backend-internal user IDs with reader-friendly text.
    nonisolated static func maskUserIDs(_ raw: String) -> String {
        var s = raw
        s = s.replacingOccurrences(of: "user_1's", with: "your", options: .caseInsensitive)
        if let re = try? NSRegularExpression(pattern: #"\buser_\d+\b"#, options: .caseInsensitive) {
            let range = NSRange(s.startIndex..<s.endIndex, in: s)
            s = re.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: "your data")
        }
        return s
    }

    /// Maps internal phase strings (e.g. "phase_1_analyzer") to a human phrase.
    nonisolated static func phaseDisplay(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("synth") { return "Drafting your answer" }
        if lower.contains("radar") { return "Scanning for peer signals" }
        if lower.contains("peer") { return "Listening for peer wisdom" }
        if lower.contains("analyz") { return "Analyzing your biometrics" }
        if lower.contains("phase_1") { return "Analyzing your biometrics" }
        if lower.contains("phase_2") { return "Scanning for peer signals" }
        if lower.contains("phase_3") { return "Drafting your answer" }
        let masked = maskUserIDs(raw)
        guard let first = masked.first else { return masked }
        return first.uppercased() + masked.dropFirst()
    }

    /// Strips `_user_N` suffix from agent identifiers.
    nonisolated static func friendlyAgent(_ raw: String) -> String {
        var s = raw
        if let re = try? NSRegularExpression(pattern: #"_user_\d+"#, options: .caseInsensitive) {
            let range = NSRange(s.startIndex..<s.endIndex, in: s)
            s = re.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: "")
        }
        return s.replacingOccurrences(of: "_", with: " ")
    }

    nonisolated static func toolDisplay(_ tool: String) -> String {
        switch tool {
        case "publish_shout":   return "broadcast a peer signal"
        case "read_replies_for": return "read peer replies"
        default:                 return tool.replacingOccurrences(of: "_", with: " ")
        }
    }

    /// Pretty-print a backend peer_label like "user_3" → "Peer 3".
    nonisolated static func prettyPeer(_ raw: String) -> String {
        if let match = raw.range(of: #"^user_(\d+)$"#, options: .regularExpression) {
            let n = raw[match].dropFirst("user_".count)
            return "Peer \(n)"
        }
        return raw.replacingOccurrences(of: "_", with: " ").capitalized
    }

    // MARK: - Peer / exchange state mutators

    private func upsertPeer(label: String, state: PeerNode.State) {
        if let idx = peers.firstIndex(where: { $0.label == label }) {
            peers[idx].state = state
        } else {
            peers.append(PeerNode(label: label, state: state))
        }
    }

    private func recordExchange(peer: String, status: PeerExchange.Status) {
        if let idx = exchanges.firstIndex(where: { $0.peer == peer && $0.status == .pending }) {
            // Same peer's pending exchange resolves to its replied state in place.
            exchanges[idx].status = status
        } else {
            exchanges.insert(
                PeerExchange(peer: peer, status: status, timestamp: Date()),
                at: 0
            )
            if exchanges.count > 6 { exchanges.removeLast(exchanges.count - 6) }
        }
    }

    private func appendEvent(_ event: BackendEvent) {
        feed.append(event)
        if feed.count > 200 { feed.removeFirst(feed.count - 200) }
    }

    // MARK: Disconnect / reconnect

    private func handleDisconnect() {
        isConnected = false
        isThinking = false
        currentPhase = nil
        isChatStreaming = false
        closeSocket()
        guard !manuallyDisconnected else { return }
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        cancelReconnect()
        let attempt = reconnectAttempt
        reconnectAttempt += 1
        let delay = min(pow(2.0, Double(attempt)), 30.0) // 1, 2, 4, 8, 16, 30, 30…
        statusText = "Reconnecting in \(Int(delay))s…"
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.openSocket()
            }
        }
    }

    private static let shortTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}

// MARK: - URLSessionWebSocketDelegate

extension BackendClient: URLSessionWebSocketDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        Task { @MainActor in
            self.handleSocketOpened()
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        Task { @MainActor in
            self.handleDisconnect()
        }
    }

    private func handleSocketOpened() {
        isConnected = true
        reconnectAttempt = 0
        statusText = "Connected · \(host):\(port)/ws"
        // Initial connect handshake the backend expects.
        sendJSON(["type": "connect", "user_id": userID])
    }
}

// MARK: - Event model

struct BackendEvent: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let kind: Kind
    let label: String

    enum Kind: String {
        case agentStep
        case toolCall
        case toolResult
        case shoutPublished
        case peerActive
        case peerReply
        case agentText
        case noAnomaly
        case synthesis
        case chatToken
        case system
    }
}

struct PeerNode: Identifiable, Equatable {
    let id = UUID()
    let label: String
    var state: State

    enum State: String {
        case pending
        case replied
    }
}

struct PeerExchange: Identifiable, Equatable {
    let id = UUID()
    let peer: String
    var status: Status
    let timestamp: Date

    enum Status: String {
        case pending
        case replied
        case answered
    }
}
