//
//  NetworkScreen.swift
//  PeerHealth
//
//  Visualizes the live agent↔agent network during a `analyze` run.
//  Tapping the Analyze button sends a fresh `ask` over WS; as
//  shout_published / peer_active / peer_reply / synthesis events arrive,
//  the graph and exchange list animate accordingly.
//

import SwiftUI

struct NetworkScreen: View {
    @ObservedObject var backend: BackendClient

    var body: some View {
        PointerTrackingScreen { pointer in
            screenBody(pointer: pointer)
        }
    }

    @ViewBuilder
    private func screenBody(pointer: UnitPoint?) -> some View {
        ZStack {
            Color(red: 0.99, green: 0.97, blue: 0.96).ignoresSafeArea()
            JellyBackground(palette: .iridescent,
                            blur: 100,
                            intensity: 1.4,
                            speed: 0.8,
                            opacity: 0.95,
                            pointer: pointer)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    headerBar
                        .padding(.horizontal, 22)
                        .padding(.top, 6)

                    headline
                        .padding(.horizontal, 22)
                        .padding(.top, 22)

                    NetworkGraph(backend: backend)
                        .frame(height: 360)
                        .padding(.top, 20)

                    if backend.latestSynthesis != nil || backend.latestNoAnomalySummary != nil {
                        synthesisCard
                            .padding(.horizontal, 18)
                            .padding(.top, 16)
                    }

                    exchangesSection
                        .padding(.horizontal, 18)
                        .padding(.top, 22)

                    Spacer(minLength: 24)

                    analyzeButton
                        .padding(.horizontal, 22)
                        .padding(.top, 18)
                        .padding(.bottom, 8)
                }
                .padding(.bottom, 130)
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Text("NETWORK · WHO'S CONNECTED")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Color.black.opacity(0.5))
            Spacer()
            HStack(spacing: 5) {
                Circle()
                    .fill(backend.isConnected
                          ? Color(red: 0.20, green: 0.78, blue: 0.35)
                          : Color(red: 0.95, green: 0.66, blue: 0.07))
                    .frame(width: 7, height: 7)
                Text(backend.isConnected ? "LIVE" : "OFFLINE")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.4)
                    .foregroundStyle(Color.black.opacity(0.55))
            }
        }
    }

    // MARK: - Headline

    private var headline: some View {
        VStack(alignment: .leading, spacing: 6) {
            headlineText
                .font(.custom("Times New Roman", size: 30))
                .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.09))
            Text("They share what you allow — never raw data.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.55))
        }
    }

    private var headlineText: Text {
        let count = backend.peers.count
        if backend.isThinking && count == 0 {
            return Text("Your agent is reaching out…")
        }
        if count == 0 {
            return Text("Your agent is ") + Text("standing by").italic() + Text(".")
        }
        let plural = count == 1 ? "other" : "others"
        return Text("Your agent is talking to ")
            + Text("\(count) \(plural)").italic()
            + Text(".")
    }

    // MARK: - Synthesis card

    private var synthesisCard: some View {
        let answer = backend.latestSynthesis ?? backend.latestNoAnomalySummary ?? ""
        let isCalm = backend.latestSynthesis == nil && backend.latestNoAnomalySummary != nil
        return GlassCard(padding: 18, radius: 22) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isCalm
                              ? Color(red: 0.20, green: 0.78, blue: 0.35)
                              : Color(red: 0.37, green: 0.36, blue: 0.90))
                        .frame(width: 7, height: 7)
                    Text(isCalm ? "ALL CLEAR" : "AGENT · ANSWER")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(Color.black.opacity(0.5))
                }
                Text(answer)
                    .font(.system(size: 19, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.09))
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Exchanges

    private var exchangesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LIVE EXCHANGES")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Color.black.opacity(0.5))

            if backend.exchanges.isEmpty {
                Text(backend.isThinking ? "waiting on first peer…" : "no exchanges yet — tap Analyze")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.black.opacity(0.45))
                    .padding(.horizontal, 4)
            } else {
                VStack(spacing: 8) {
                    ForEach(backend.exchanges) { ex in
                        ExchangeRow(exchange: ex)
                    }
                }
            }
        }
    }

    // MARK: - Analyze button

    private var analyzeButton: some View {
        Button(action: tapAnalyze) {
            HStack(spacing: 8) {
                if backend.isThinking {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.85)
                }
                Text(buttonTitle)
                    .font(.system(size: 16, weight: .bold))
                    .tracking(-0.2)
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                Capsule().fill(buttonGradient)
            )
            .shadow(color: .black.opacity(0.18), radius: 18, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(!backend.isConnected || backend.isThinking)
        .opacity((backend.isConnected && !backend.isThinking) ? 1 : 0.6)
    }

    private var buttonTitle: String {
        if !backend.isConnected { return "Reconnecting…" }
        if backend.isThinking { return "Agents are working…" }
        if backend.latestSynthesis != nil || backend.latestNoAnomalySummary != nil {
            return "Run another analysis"
        }
        return "Analyze with peer agents"
    }

    private var buttonGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.07, green: 0.07, blue: 0.09),
                Color(red: 0.27, green: 0.20, blue: 0.55)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func tapAnalyze() {
        backend.analyze()
    }
}

// MARK: - Exchange row

private struct ExchangeRow: View {
    let exchange: PeerExchange

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .shadow(color: statusColor.opacity(0.6), radius: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbLine)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.09))
                    .lineLimit(1)
            }
            Spacer()
            Text(statusLabel)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(statusColor)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(statusColor.opacity(0.14))
                )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.05), lineWidth: 0.5)
                )
        )
    }

    private var verbLine: AttributedString {
        let peer = BackendClient.prettyPeer(exchange.peer)
        let verb: String
        switch exchange.status {
        case .pending:
            verb = "is considering your case"
        case .replied:
            verb = "shared an insight"
        case .answered:
            verb = "answered your question"
        }
        var attr = AttributedString("\(peer)'s agent \(verb)")
        if let range = attr.range(of: "\(peer)'s agent") {
            attr[range].foregroundColor = .black
            attr[range].font = .system(size: 13, weight: .bold)
        }
        return attr
    }

    private var statusLabel: String {
        switch exchange.status {
        case .pending:  return "PENDING"
        case .replied:  return "RECEIVED"
        case .answered: return "ANSWERED"
        }
    }

    private var statusColor: Color {
        switch exchange.status {
        case .pending:  return Color(red: 0.95, green: 0.55, blue: 0.10)
        case .replied:  return Color(red: 0.37, green: 0.36, blue: 0.90)
        case .answered: return Color(red: 0.20, green: 0.62, blue: 0.35)
        }
    }
}

// MARK: - Network graph

private struct NetworkGraph: View {
    @ObservedObject var backend: BackendClient
    @State private var pulseRings: [PulseRing] = []

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60)) { context in
            let time = context.date.timeIntervalSinceReferenceDate

            GeometryReader { geo in
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                let radius = min(geo.size.width, geo.size.height) * 0.35

                ZStack {
                    // Outgoing pulse rings (one per shout_published)
                    ForEach(pulseRings) { ring in
                        PulseRingView(ring: ring,
                                      center: center,
                                      maxRadius: radius * 1.7,
                                      now: time)
                    }

                    // Edges + traveling pulses
                    ForEach(Array(backend.peers.enumerated()), id: \.element.id) { idx, peer in
                        let pos = peerPosition(index: idx,
                                               count: max(backend.peers.count, 1),
                                               center: center,
                                               radius: radius)
                        EdgeView(from: center,
                                 to: pos,
                                 peer: peer,
                                 time: time)
                    }

                    // You orb at center
                    YouOrb()
                        .frame(width: 130, height: 130)
                        .position(center)

                    Text("You · GX10")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.7))
                        .position(x: center.x, y: center.y + 78)

                    // Peer orbs
                    ForEach(Array(backend.peers.enumerated()), id: \.element.id) { idx, peer in
                        let pos = peerPosition(index: idx,
                                               count: max(backend.peers.count, 1),
                                               center: center,
                                               radius: radius)
                        PeerOrbView(peer: peer, hue: hue(for: peer.label))
                            .frame(width: 64, height: 64)
                            .position(pos)
                        Text(BackendClient.prettyPeer(peer.label))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.65))
                            .position(x: pos.x, y: pos.y + 42)
                    }

                    // Empty-state hint
                    if backend.peers.isEmpty && !backend.isThinking {
                        Text("tap analyze to wake the network")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.black.opacity(0.4))
                            .position(x: center.x, y: center.y + radius + 34)
                    }
                }
            }
        }
        .onChange(of: backend.shoutPulseToken) { _, _ in
            spawnPulseRing()
        }
    }

    private func peerPosition(index: Int, count: Int, center: CGPoint, radius: CGFloat) -> CGPoint {
        // Evenly distribute around the circle starting at top.
        let angle = -CGFloat.pi / 2 + (CGFloat(index) / CGFloat(max(count, 1))) * (2 * .pi)
        return CGPoint(x: center.x + cos(angle) * radius,
                       y: center.y + sin(angle) * radius)
    }

    private func hue(for label: String) -> Double {
        // Stable hash → hue
        var hash: UInt64 = 5381
        for byte in label.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return Double(hash % 360) / 360.0
    }

    private func spawnPulseRing() {
        let ring = PulseRing(id: UUID(), startTime: Date().timeIntervalSinceReferenceDate)
        pulseRings.append(ring)
        // Cull old rings after their lifetime (~2s).
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_300_000_000)
            pulseRings.removeAll { $0.id == ring.id }
        }
    }
}

private struct PulseRing: Identifiable, Equatable {
    let id: UUID
    let startTime: TimeInterval
}

private struct PulseRingView: View {
    let ring: PulseRing
    let center: CGPoint
    let maxRadius: CGFloat
    let now: TimeInterval

    var body: some View {
        let life: TimeInterval = 2.0
        let elapsed = max(0, min(life, now - ring.startTime))
        let t = elapsed / life
        let radius = CGFloat(t) * maxRadius
        let opacity = (1.0 - t) * 0.7

        Circle()
            .stroke(
                Color(red: 0.37, green: 0.36, blue: 0.90).opacity(opacity),
                style: StrokeStyle(lineWidth: 1.2)
            )
            .frame(width: radius * 2, height: radius * 2)
            .position(center)
    }
}

private struct EdgeView: View {
    let from: CGPoint
    let to: CGPoint
    let peer: PeerNode
    let time: TimeInterval

    var body: some View {
        ZStack {
            Path { path in
                path.move(to: from)
                path.addLine(to: to)
            }
            .stroke(
                Color.black.opacity(0.18),
                style: StrokeStyle(lineWidth: 0.6, dash: [3, 4])
            )

            // Traveling pulse along the edge — outbound while pending, inbound after reply.
            let dx = to.x - from.x
            let dy = to.y - from.y
            let dur: TimeInterval = peer.state == .replied ? 1.1 : 1.6
            let phase = (time.truncatingRemainder(dividingBy: dur)) / dur
            let p = peer.state == .replied ? (1.0 - phase) : phase
            let px = from.x + CGFloat(p) * dx
            let py = from.y + CGFloat(p) * dy
            Circle()
                .fill(peer.state == .replied
                      ? Color(red: 0.37, green: 0.36, blue: 0.90)
                      : Color(red: 0.95, green: 0.55, blue: 0.10))
                .frame(width: 6, height: 6)
                .shadow(color: (peer.state == .replied
                                ? Color(red: 0.37, green: 0.36, blue: 0.90)
                                : Color(red: 0.95, green: 0.55, blue: 0.10)).opacity(0.7),
                        radius: 4)
                .position(x: px, y: py)
        }
    }
}

// MARK: - Orbs

private struct YouOrb: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            Color(red: 1.00, green: 0.42, blue: 0.36),
                            Color(red: 0.97, green: 0.83, blue: 0.40),
                            Color(red: 0.31, green: 0.82, blue: 0.77),
                            Color(red: 0.77, green: 0.66, blue: 1.0),
                            Color(red: 1.00, green: 0.42, blue: 0.36)
                        ]),
                        center: .center
                    )
                )
                .blur(radius: 8)
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.6),
                            Color.white.opacity(0)
                        ]),
                        center: UnitPoint(x: 0.32, y: 0.28),
                        startRadius: 4,
                        endRadius: 70
                    )
                )
                .blendMode(.plusLighter)
            Circle()
                .strokeBorder(Color.white.opacity(0.55), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.12), radius: 20, y: 6)
    }
}

private struct PeerOrbView: View {
    let peer: PeerNode
    let hue: Double
    @State private var phase: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color(hue: hue, saturation: 0.35, brightness: 1.0),
                            Color(hue: hue, saturation: 0.55, brightness: 0.75)
                        ]),
                        center: UnitPoint(x: 0.4, y: 0.35),
                        startRadius: 4,
                        endRadius: 36
                    )
                )
                .opacity(peer.state == .replied ? 1.0 : 0.55)

            Circle()
                .strokeBorder(
                    peer.state == .replied
                    ? Color(red: 0.37, green: 0.36, blue: 0.90).opacity(0.9)
                    : Color.white.opacity(0.5),
                    lineWidth: peer.state == .replied ? 1.4 : 0.6
                )
                .scaleEffect(peer.state == .pending ? 1.0 + 0.06 * sin(phase) : 1.0)
        }
        .shadow(color: Color(hue: hue, saturation: 0.5, brightness: 0.7).opacity(0.4),
                radius: 8)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                phase = .pi
            }
        }
        .animation(.easeInOut(duration: 0.4), value: peer.state)
    }
}
