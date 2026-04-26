//
//  TCPConnectionManager.swift
//  PeerHealth
//

import Combine
import Foundation
import Network

@MainActor
final class TCPConnectionManager: ObservableObject {
    @Published var host: String {
        didSet { UserDefaults.standard.set(host, forKey: "peerHealthHost") }
    }
    @Published var port: String {
        didSet { UserDefaults.standard.set(port, forKey: "peerHealthPort") }
    }
    @Published private(set) var statusText = "Disconnected"
    @Published private(set) var isConnected = false

    private let queue = DispatchQueue(label: "PeerHealth.TCPConnection")
    private var connection: NWConnection?

    init() {
        let storedHost = UserDefaults.standard.string(forKey: "peerHealthHost")
        self.host = (storedHost?.isEmpty == false) ? storedHost! : "10.30.77.124"
        let storedPort = UserDefaults.standard.string(forKey: "peerHealthPort")
        self.port = (storedPort?.isEmpty == false) ? storedPort! : "8000"
    }

    func connect(onReceive: @escaping (String) -> Void) {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPort = port.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedHost.isEmpty else {
            statusText = "Enter the Asus computer IP address."
            return
        }

        guard let nwPort = NWEndpoint.Port(trimmedPort) else {
            statusText = "Enter a valid TCP port."
            return
        }

        disconnect()

        statusText = "Connecting to \(trimmedHost):\(trimmedPort)..."

        let connection = NWConnection(host: NWEndpoint.Host(trimmedHost), port: nwPort, using: .tcp)
        self.connection = connection

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }

            Task { @MainActor in
                switch state {
                case .ready:
                    self.isConnected = true
                    self.statusText = "Connected to \(trimmedHost):\(trimmedPort)"
                    self.receiveNextMessage(onReceive: onReceive)
                case .failed(let error):
                    self.isConnected = false
                    self.statusText = "Connection failed: \(error.localizedDescription)"
                    self.connection = nil
                case .waiting(let error):
                    self.isConnected = false
                    self.statusText = "Waiting for network: \(error.localizedDescription)"
                case .cancelled:
                    self.isConnected = false
                    self.statusText = "Disconnected"
                    self.connection = nil
                default:
                    break
                }
            }
        }

        connection.start(queue: queue)
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        isConnected = false
        statusText = "Disconnected"
    }

    func send(_ message: String) {
        guard let connection, isConnected else {
            statusText = "Connect before sending a message."
            return
        }

        let payload = Data((message + "\n").utf8)
        connection.send(content: payload, completion: .contentProcessed { [weak self] error in
            guard let self else { return }

            Task { @MainActor in
                if let error {
                    self.statusText = "Send failed: \(error.localizedDescription)"
                    self.isConnected = false
                } else {
                    self.statusText = "Sent to \(self.host):\(self.port)"
                }
            }
        })
    }

    private func receiveNextMessage(onReceive: @escaping (String) -> Void) {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let data, !data.isEmpty, let message = String(data: data, encoding: .utf8) {
                Task { @MainActor in
                    onReceive(message.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }

            if let error {
                Task { @MainActor in
                    self.isConnected = false
                    self.statusText = "Receive failed: \(error.localizedDescription)"
                    self.connection = nil
                }
                return
            }

            if isComplete {
                Task { @MainActor in
                    self.isConnected = false
                    self.statusText = "Remote host closed the connection."
                    self.connection = nil
                }
                return
            }

            Task { @MainActor in
                self.receiveNextMessage(onReceive: onReceive)
            }
        }
    }
}
