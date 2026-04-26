//
//  QAClient.swift
//  PeerHealth
//
//  Per-question WebSocket client for the backend's /ws/qa health Q&A endpoint.
//  Each ask() opens a fresh socket, drives the connect → chat_started → qa →
//  qa_answer flow, and tears the socket down. Independent of BackendClient's
//  long-lived /ws orchestrator socket.
//

import Combine
import Foundation

@MainActor
final class QAClient: NSObject, ObservableObject {

    // MARK: Published state

    @Published private(set) var isAsking: Bool = false
    @Published private(set) var currentToolLabel: String?
    @Published private(set) var lastError: String?

    // MARK: Internals

    private weak var backend: BackendClient?
    private var webSocket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private lazy var urlSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.waitsForConnectivity = true
        cfg.timeoutIntervalForRequest = 30
        return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }()

    private var pendingQuestion: String?
    private var onAnswer: ((String) -> Void)?
    private var generation: Int = 0

    // MARK: Setup

    /// Wires the QA client to the same backend that owns host/port/userID.
    /// Call from `.onAppear` since `@StateObject` requires a no-arg init.
    func attach(backend: BackendClient) {
        self.backend = backend
    }

    // MARK: Public API

    /// Opens a fresh /ws/qa connection, sends the question, and invokes
    /// `onAnswer` once with the qa_answer text. Cancels any previous in-flight
    /// ask.
    func ask(_ text: String, onAnswer: @escaping (String) -> Void) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let backend else {
            lastError = "QAClient not attached to backend"
            return
        }

        cancel()

        let host = backend.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = backend.port.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !host.isEmpty,
            !port.isEmpty,
            let url = URL(string: "ws://\(host):\(port)/ws/qa")
        else {
            lastError = "Invalid host/port"
            return
        }

        lastError = nil
        currentToolLabel = nil
        isAsking = true
        pendingQuestion = trimmed
        self.onAnswer = onAnswer

        generation += 1
        let myGen = generation

        print("[QAClient] opening \(url.absoluteString) for question: \(trimmed)")
        let task = urlSession.webSocketTask(with: url)
        webSocket = task
        task.resume()

        receiveTask = Task { [weak self] in
            await self?.receiveLoop(generation: myGen)
        }
    }

    /// Closes any in-flight socket and clears transient state.
    func cancel() {
        generation += 1
        receiveTask?.cancel()
        receiveTask = nil
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        pendingQuestion = nil
        onAnswer = nil
        if isAsking { isAsking = false }
        currentToolLabel = nil
    }

    // MARK: Receive loop

    private func receiveLoop(generation myGen: Int) async {
        while !Task.isCancelled, myGen == self.generation, let socket = webSocket {
            do {
                let message = try await socket.receive()
                await MainActor.run {
                    guard myGen == self.generation else { return }
                    self.handleIncoming(message)
                }
            } catch {
                await MainActor.run {
                    guard myGen == self.generation else { return }
                    self.fail(with: "Receive failed: \(error.localizedDescription)")
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
        guard
            let text,
            let data = text.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let typeStr = json["type"] as? String
        else { return }

        switch typeStr {
        case "chat_started":
            let chatID = (json["chat_id"] as? String) ?? "?"
            print("[QAClient] chat_started chat_id=\(chatID)")
            if let q = pendingQuestion {
                pendingQuestion = nil
                print("[QAClient] sending qa frame: \(q)")
                sendJSON(["type": "qa", "text": q])
            }

        case "tool_call":
            let tool = (json["tool"] as? String) ?? ""
            print("[QAClient] tool_call \(tool)")
            currentToolLabel = Self.toolLabel(for: tool)

        case "tool_result":
            let tool = (json["tool"] as? String) ?? ""
            print("[QAClient] tool_result \(tool)")

        case "qa_answer":
            let answer = BackendClient.maskUserIDs((json["text"] as? String) ?? "")
            print("[QAClient] qa_answer (\(answer.count) chars)")
            let cb = onAnswer
            onAnswer = nil
            isAsking = false
            currentToolLabel = nil
            cb?(answer)
            closeSocket()

        case "error":
            let msg = (json["message"] as? String) ?? "Unknown error"
            print("[QAClient] error: \(msg)")
            fail(with: msg)

        default:
            print("[QAClient] unknown frame type=\(typeStr)")
        }
    }

    // MARK: Send

    private func sendJSON(_ dict: [String: Any]) {
        guard let socket = webSocket else { return }
        guard
            let data = try? JSONSerialization.data(withJSONObject: dict),
            let str = String(data: data, encoding: .utf8)
        else { return }
        socket.send(.string(str)) { [weak self] error in
            guard let error else { return }
            Task { @MainActor in
                self?.fail(with: "Send failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: Failure / cleanup

    private func fail(with message: String) {
        lastError = message
        isAsking = false
        currentToolLabel = nil
        pendingQuestion = nil
        onAnswer = nil
        closeSocket()
    }

    private func closeSocket() {
        receiveTask?.cancel()
        receiveTask = nil
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
    }

    // MARK: Tool label mapping

    private static func toolLabel(for tool: String) -> String {
        switch tool {
        case "get_metric_trend":   return "checking your trend"
        case "compare_to_cohort":  return "comparing to peers"
        case "read_user_summary":  return "reading your summary"
        default:                   return tool.replacingOccurrences(of: "_", with: " ")
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension QAClient: URLSessionWebSocketDelegate {
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
            // If the socket closed before qa_answer, surface as a failure.
            if self.isAsking {
                self.fail(with: "Connection closed unexpectedly")
            }
        }
    }

    private func handleSocketOpened() {
        guard let backend else { return }
        print("[QAClient] socket opened, sending connect for user_id=\(backend.userID)")
        sendJSON(["type": "connect", "user_id": backend.userID])
    }
}
