//
//  ChatScreen.swift
//  PeerHealth
//

import SwiftUI
import UIKit

struct PHChatMessage: Identifiable, Equatable {
    enum Role: Equatable { case agent, user }
    let id = UUID()
    let role: Role
    var text: String
}

struct ChatScreen: View {
    @ObservedObject var backend: BackendClient
    @ObservedObject var autoSyncManager: HealthAutoSyncManager
    @StateObject private var qa = QAClient()

    @AppStorage("peerHealthCompanionName") private var companionName = "GX10"

    @State private var draft: String = ""
    @State private var messages: [PHChatMessage] = []
    @State private var showConnectionSheet = false
    @State private var keyboardHeight: CGFloat = 0
    @FocusState private var composerFocused: Bool

    var body: some View {
        PointerTrackingScreen { pointer in
            screenBody(pointer: pointer)
        }
    }

    @ViewBuilder
    private func screenBody(pointer: UnitPoint?) -> some View {
        ZStack {
            Color(red: 0.97, green: 0.96, blue: 0.95).ignoresSafeArea()
            JellyBackground(palette: .iridescent, blur: 90, intensity: 1.3, speed: 0.7, opacity: 0.95, pointer: pointer)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(messages) { m in
                            ChatBubble(message: m)
                        }
                        if qa.isAsking {
                            TypingDots()
                                .padding(.leading, 14)
                                .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 200)
                }

                Spacer(minLength: 0)
            }

            VStack(spacing: 0) {
                Spacer()
                if let status = qaStatusText {
                    Text(status)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.55))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(Color.white.opacity(0.85))
                        )
                        .padding(.bottom, 6)
                        .transition(.opacity)
                }
                composer
                    .padding(.horizontal, 12)
                    .padding(.bottom, keyboardHeight > 0 ? keyboardHeight + 8 : 96)
            }
            .animation(.easeOut(duration: 0.25), value: keyboardHeight)
            .animation(.easeInOut(duration: 0.2), value: qaStatusText)
        }
        .sheet(isPresented: $showConnectionSheet) {
            ConnectionSheet(backend: backend, autoSyncManager: autoSyncManager)
                .presentationDetents([.medium, .large])
        }
        .onAppear { qa.attach(backend: backend) }
        .onDisappear { qa.cancel() }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notif in
            guard let frame = notif.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let screenHeight = UIScreen.main.bounds.height
            keyboardHeight = max(0, screenHeight - frame.origin.y)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
        }
    }

    private var qaStatusText: String? {
        if let err = qa.lastError, !qa.isAsking { return "Q&A error: \(err)" }
        if qa.isAsking {
            if let label = qa.currentToolLabel { return "Thinking · \(label)" }
            return "Thinking…"
        }
        return nil
    }

    private var header: some View {
        HStack(spacing: 12) {
            JellyDisc(blur: 6, intensity: 1.0, speed: 1.2)
                .frame(width: 50, height: 50)
                .frame(width: 38, height: 38)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.1), radius: 6, y: 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(agentTitle)
                    .font(.system(size: 16, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.09))

                HStack(spacing: 5) {
                    Circle()
                        .fill(backend.isConnected ? Color(red: 0.20, green: 0.78, blue: 0.35) : Color(red: 0.95, green: 0.66, blue: 0.07))
                        .frame(width: 6, height: 6)
                    Text(statusLine)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.55))
                }
            }

            Spacer()

            Button {
                showConnectionSheet = true
            } label: {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(red: 0.20, green: 0.78, blue: 0.35))
            }
            .buttonStyle(.plain)
        }
    }

    private var agentTitle: String {
        let raw = companionName.trimmingCharacters(in: .whitespaces)
        return raw.isEmpty ? "Your agent" : raw
    }

    private var statusLine: String {
        let companion = companionName.trimmingCharacters(in: .whitespaces)
        let label = companion.isEmpty ? "GX10" : companion
        return backend.isConnected ? "Live · \(label)" : "Offline · \(label)"
    }

    private var composer: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color.white.opacity(0.7))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.08), radius: 20, y: 6)

            HStack(spacing: 8) {
                Circle()
                    .fill(Color.black.opacity(0.04))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.black.opacity(0.5))
                    )

                TextField("Ask about your health…", text: $draft)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color(red: 0.07, green: 0.07, blue: 0.09))
                    .tint(Color(red: 0.07, green: 0.07, blue: 0.09))
                    .focused($composerFocused)
                    .submitLabel(.send)
                    .onSubmit { send() }

                Button {
                    send()
                } label: {
                    LinearGradient(
                        colors: [
                            Color(red: 1.0,  green: 0.42, blue: 0.36),
                            Color(red: 0.77, green: 0.66, blue: 1.0),
                            Color(red: 0.31, green: 0.82, blue: 0.77)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                    .overlay(
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                    )
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                }
                .buttonStyle(.plain)
            }
            .padding(6)
        }
        .frame(height: 52)
        .environment(\.colorScheme, .light)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messages.append(.init(role: .user, text: text))

        let pending = PHChatMessage(role: .agent, text: "")
        let pendingID = pending.id
        messages.append(pending)
        draft = ""

        qa.ask(text) { answer in
            let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
            if let idx = messages.firstIndex(where: { $0.id == pendingID }) {
                if trimmed.isEmpty {
                    messages.remove(at: idx)
                } else {
                    messages[idx].text = trimmed
                }
            } else if !trimmed.isEmpty {
                messages.append(.init(role: .agent, text: trimmed))
            }
        }
    }
}

private struct ChatBubble: View {
    let message: PHChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }

            Text(message.text.isEmpty ? "…" : message.text)
                .font(.system(size: 15, weight: .medium))
                .tracking(-0.2)
                .lineSpacing(2)
                .foregroundStyle(message.role == .user ? .white : Color(red: 0.07, green: 0.07, blue: 0.09))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(bubbleBackground)
                .frame(maxWidth: 300, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .agent { Spacer(minLength: 40) }
        }
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if message.role == .user {
            BubbleShape(corner: 20, tail: .right)
                .fill(LinearGradient(
                    colors: [Color(red: 0.07, green: 0.07, blue: 0.09), Color(red: 0.16, green: 0.16, blue: 0.18)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
        } else {
            BubbleShape(corner: 20, tail: .left)
                .fill(.ultraThinMaterial)
                .overlay(
                    BubbleShape(corner: 20, tail: .left)
                        .fill(Color.white.opacity(0.55))
                )
                .overlay(
                    BubbleShape(corner: 20, tail: .left)
                        .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
        }
    }
}

private struct BubbleShape: Shape {
    enum Tail { case left, right }
    let corner: CGFloat
    let tail: Tail

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let tlc = corner
        let trc = corner
        let brc: CGFloat = tail == .right ? 6 : corner
        let blc: CGFloat = tail == .left ? 6 : corner

        p.move(to: CGPoint(x: rect.minX + tlc, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - trc, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + trc), control: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - brc))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - brc, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + blc, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - blc), control: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tlc))
        p.addQuadCurve(to: CGPoint(x: rect.minX + tlc, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

private struct TypingDots: View {
    var body: some View {
        TimelineView(.animation) { context in
            let now = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Color.black.opacity(0.5))
                        .frame(width: 7, height: 7)
                        .opacity(opacity(now: now, index: i))
                        .scaleEffect(scale(now: now, index: i))
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func phase(now: Double, index: Int) -> Double {
        let cycle = 1.1
        let stagger = Double(index) * 0.18
        return ((now + stagger).truncatingRemainder(dividingBy: cycle)) / cycle
    }

    private func opacity(now: Double, index: Int) -> Double {
        let p = phase(now: now, index: index)
        // Fade between 0.35 and 1.0 across the cycle.
        return 0.35 + 0.65 * (0.5 - 0.5 * cos(p * 2 * .pi))
    }

    private func scale(now: Double, index: Int) -> CGFloat {
        let p = phase(now: now, index: index)
        return 0.85 + 0.25 * (0.5 - 0.5 * cos(p * 2 * .pi))
    }
}

// MARK: - Connection sheet

private struct ConnectionSheet: View {
    @ObservedObject var backend: BackendClient
    @ObservedObject var autoSyncManager: HealthAutoSyncManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Backend (GX10)") {
                    HStack {
                        Text("IP address")
                        Spacer()
                        TextField(BackendClient.defaultHost, text: $backend.host)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Port")
                        Spacer()
                        TextField(BackendClient.defaultPort, text: $backend.port)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("User ID")
                        Spacer()
                        TextField(BackendClient.defaultUserID, text: $backend.userID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(backend.statusText)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    Button(backend.isConnected ? "Reconnect" : "Connect") {
                        backend.reconnectFromSettings()
                    }
                    if backend.isConnected {
                        Button("Disconnect", role: .destructive) {
                            backend.disconnect()
                        }
                    }
                }

                Section("HealthKit auto sync") {
                    Text(autoSyncManager.statusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let when = autoSyncManager.lastChangeAt {
                        Text("Last data change: \(Self.timeFormatter.string(from: when))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .medium
        return f
    }()
}
