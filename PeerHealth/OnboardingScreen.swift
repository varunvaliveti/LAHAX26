//
//  OnboardingScreen.swift
//  PeerHealth
//

import SwiftUI

struct OnboardingScreen: View {
    @AppStorage("peerHealthHasOnboarded") private var hasOnboarded = false
    @AppStorage("peerHealthUserName") private var userName = ""
    @AppStorage("peerHealthCompanionName") private var companionName = ""
    @AppStorage("peerHealthHost") private var host = "100.75.187.58"

    @State private var step: Int = 0
    @State private var draftName: String = ""
    @State private var draftCompanion: String = ""
    @State private var draftHost: String = ""

    var body: some View {
        PointerTrackingScreen { pointer in
            screenBody(pointer: pointer)
        }
    }

    @ViewBuilder
    private func screenBody(pointer: UnitPoint?) -> some View {
        ZStack {
            Color(red: 0.98, green: 0.97, blue: 0.96).ignoresSafeArea()
            JellyBackground(palette: .iridescent, blur: 45, intensity: 1.1, speed: 0.7, opacity: 0.95, pointer: pointer)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                progressDots
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                Group {
                    switch step {
                    case 0:
                        WelcomeStep(onNext: { withAnimation(.easeInOut(duration: 0.35)) { step = 1 } })
                    case 1:
                        FormStep(
                            name: $draftName,
                            companion: $draftCompanion,
                            host: $draftHost,
                            onBack: { withAnimation(.easeInOut(duration: 0.35)) { step = 0 } },
                            onNext: { withAnimation(.easeInOut(duration: 0.35)) { step = 2 } }
                        )
                    default:
                        ConnectingStep(
                            name: draftName,
                            companion: draftCompanion,
                            host: draftHost,
                            onDone: finish
                        )
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .onAppear {
            draftName = userName
            draftCompanion = companionName
            draftHost = host.isEmpty ? "100.75.187.58" : host
        }
    }

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(i <= step ? Color(red: 0.07, green: 0.07, blue: 0.09) : Color.black.opacity(0.15))
                    .frame(width: i == step ? 22 : 6, height: 6)
                    .animation(.easeInOut(duration: 0.35), value: step)
            }
        }
    }

    private func finish() {
        userName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        companionName = draftCompanion.trimmingCharacters(in: .whitespacesAndNewlines)
        host = draftHost.trimmingCharacters(in: .whitespacesAndNewlines)
        hasOnboarded = true
    }
}

// MARK: - Step 0: Welcome

private struct WelcomeStep: View {
    var onNext: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                JellyDisc(blur: 14, intensity: 1.05, speed: 0.9)
                    .frame(width: 240, height: 240)
                    .frame(width: 200, height: 200)
                    .clipShape(Circle())

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(0.55), Color.white.opacity(0)],
                            center: UnitPoint(x: 0.35, y: 0.30),
                            startRadius: 0,
                            endRadius: 140
                        )
                    )
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 0.5))
                    .frame(width: 200, height: 200)
                    .shadow(color: .black.opacity(0.12), radius: 30, x: 0, y: 30)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 0) {
                Text("PEERHEALTH")
                    .font(.system(size: 13, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(Color.black.opacity(0.5))

                serifHeadline
                    .padding(.top, 6)

                Text("A private AI companion that talks to your Apple Health data — over a direct connection to a machine you own.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.black.opacity(0.55))
                    .lineSpacing(3)
                    .padding(.top, 12)

                Button(action: onNext) {
                    Text("Get started")
                        .font(.system(size: 16, weight: .bold))
                        .tracking(-0.2)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            Capsule().fill(Color(red: 0.07, green: 0.07, blue: 0.09))
                        )
                        .shadow(color: .black.opacity(0.18), radius: 20, y: 8)
                }
                .buttonStyle(.plain)
                .padding(.top, 20)

                HStack(spacing: 5) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(red: 0.20, green: 0.78, blue: 0.35))
                    Text("No cloud · No third parties")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.42))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
    }

    private var serifHeadline: some View {
        Text("Your health, on ")
            .font(.custom("Times New Roman", size: 44))
            .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.09))
        +
        Text("your")
            .font(.custom("Times New Roman", size: 44).italic())
            .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.09))
        +
        Text(" hardware.")
            .font(.custom("Times New Roman", size: 44))
            .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.09))
    }
}

// MARK: - Step 1: Form

private struct FormStep: View {
    @Binding var name: String
    @Binding var companion: String
    @Binding var host: String

    var onBack: () -> Void
    var onNext: () -> Void

    @FocusState private var focused: FocusField?

    private enum FocusField: Hashable { case name, companion, host }

    private var canContinue: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !companion.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                    Text("Back")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(Color.black.opacity(0.5))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            VStack(alignment: .leading, spacing: 8) {
                Text("Let's get you\nconnected.")
                    .font(.custom("Times New Roman", size: 36))
                    .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.09))
                    .lineSpacing(0)

                Text("Tell your agent what to call you, and what your AI companion's name is.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.black.opacity(0.55))
                    .lineSpacing(3)
            }
            .padding(.top, 18)

            VStack(spacing: 12) {
                OBField(
                    label: "Your name",
                    placeholder: "Akhil",
                    systemImage: "person.fill",
                    text: $name,
                    isFocused: focused == .name,
                    monospaced: false
                )
                .focused($focused, equals: .name)

                OBField(
                    label: "AI companion's name",
                    placeholder: "Sage",
                    systemImage: "sparkles",
                    text: $companion,
                    isFocused: focused == .companion,
                    monospaced: false
                )
                .focused($focused, equals: .companion)

                OBField(
                    label: "Network address",
                    placeholder: "100.75.187.58",
                    systemImage: "globe",
                    text: $host,
                    isFocused: focused == .host,
                    monospaced: true
                )
                .focused($focused, equals: .host)
            }
            .padding(.top, 22)

            Spacer(minLength: 0)

            Button(action: { if canContinue { onNext() } }) {
                Text("Connect")
                    .font(.system(size: 16, weight: .bold))
                    .tracking(-0.2)
                    .foregroundStyle(canContinue ? .white : Color.black.opacity(0.4))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        Capsule().fill(canContinue
                                       ? Color(red: 0.07, green: 0.07, blue: 0.09)
                                       : Color.black.opacity(0.12))
                    )
                    .shadow(color: canContinue ? .black.opacity(0.18) : .clear,
                            radius: canContinue ? 20 : 0, y: canContinue ? 8 : 0)
                    .animation(.easeOut(duration: 0.2), value: canContinue)
            }
            .buttonStyle(.plain)
            .disabled(!canContinue)

            HStack(spacing: 5) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(red: 0.20, green: 0.78, blue: 0.35))
                Text("Direct WebSocket · stays on your network")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.45))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 24)
    }
}

private struct OBField: View {
    let label: String
    let placeholder: String
    let systemImage: String
    @Binding var text: String
    var isFocused: Bool
    var monospaced: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.7))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            isFocused ? Color(red: 0.07, green: 0.07, blue: 0.09) : Color.black.opacity(0.08),
                            lineWidth: isFocused ? 1.5 : 0.5
                        )
                )
                .shadow(color: isFocused ? Color.black.opacity(0.06) : Color.black.opacity(0.03),
                        radius: isFocused ? 4 : 1, y: 0)
                .animation(.easeOut(duration: 0.15), value: isFocused)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.45))
                    Text(label.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.4)
                        .foregroundStyle(Color.black.opacity(0.55))
                }
                TextField(placeholder, text: $text)
                    .font(.system(size: 17, weight: .semibold,
                                  design: monospaced ? .monospaced : .default))
                    .tracking(-0.3)
                    .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.09))
                    .textInputAutocapitalization(monospaced ? .never : .words)
                    .autocorrectionDisabled(monospaced)
                    .keyboardType(monospaced ? .numbersAndPunctuation : .default)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
    }
}

// MARK: - Step 2: Connecting

private struct ConnectingStep: View {
    let name: String
    let companion: String
    let host: String
    var onDone: () -> Void

    @State private var phase: Phase = .connecting
    @State private var spin: Double = 0

    private enum Phase { case connecting, connected }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ZStack {
                JellyDisc(blur: 12, intensity: 1.05, speed: phase == .connected ? 1.2 : 0.7)
                    .frame(width: 220, height: 220)
                    .frame(width: 180, height: 180)
                    .clipShape(Circle())

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(0.55), Color.white.opacity(0)],
                            center: UnitPoint(x: 0.35, y: 0.30),
                            startRadius: 0,
                            endRadius: 130
                        )
                    )
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 0.5))
                    .frame(width: 180, height: 180)

                ringView
                    .frame(width: 180, height: 180)
            }

            Spacer()

            VStack(spacing: 8) {
                Text(headline)
                    .font(.custom("Times New Roman", size: 30))
                    .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.09))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Text(subtitle)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Color.black.opacity(0.55))

                if phase == .connected {
                    Button(action: onDone) {
                        Text("Take me home")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Capsule().fill(Color(red: 0.07, green: 0.07, blue: 0.09)))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 28)
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(.bottom, 36)
        }
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                spin = 360
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                withAnimation(.easeInOut(duration: 0.6)) {
                    phase = .connected
                }
            }
        }
    }

    @ViewBuilder
    private var ringView: some View {
        switch phase {
        case .connecting:
            Circle()
                .trim(from: 0, to: 0.1)
                .stroke(Color(red: 0.07, green: 0.07, blue: 0.09),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(spin - 90))
        case .connected:
            Circle()
                .stroke(Color(red: 0.20, green: 0.78, blue: 0.35),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }

    private var headline: String {
        switch phase {
        case .connecting:
            return "Reaching \(companion.isEmpty ? "your companion" : companion)…"
        case .connected:
            return "Hi \(name.isEmpty ? "there" : name) — you're in."
        }
    }

    private var subtitle: String {
        switch phase {
        case .connecting:
            return "ws://\(host):8000/ws"
        case .connected:
            return "linked · \(companion.isEmpty ? "GX10" : companion)"
        }
    }
}
