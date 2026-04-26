//
//  ProfileScreen.swift
//  PeerHealth
//

import SwiftUI

struct ProfileScreen: View {
    @ObservedObject var viewModel: HealthDashboardViewModel
    @ObservedObject var backend: BackendClient
    @ObservedObject var autoSyncManager: HealthAutoSyncManager
    @Binding var useDemoData: Bool

    @AppStorage("peerHealthCompanionName") private var companionName = "GX10"
    @AppStorage("peerHealthUserName") private var userName = ""
    @AppStorage("peerHealthHasOnboarded") private var hasOnboarded = false

    @State private var showConnectionSheet = false
    @State private var showSignOutConfirm = false

    var body: some View {
        PointerTrackingScreen { pointer in
            screenBody(pointer: pointer)
        }
    }

    @ViewBuilder
    private func screenBody(pointer: UnitPoint?) -> some View {
        ZStack {
            Color(red: 0.97, green: 0.96, blue: 0.95).ignoresSafeArea()
            JellyBackground(palette: .iridescent, blur: 85, intensity: 1.3, speed: 0.7, opacity: 1.0, pointer: pointer)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    avatarHeader
                        .padding(.horizontal, 22)
                        .padding(.top, 8)

                    connectionCard
                        .padding(.horizontal, 16)
                        .padding(.top, 20)

                    SectionLabel(text: "Health data")
                        .padding(.horizontal, 16)
                        .padding(.top, 16)

                    settingsGroup(rows: [
                        .init(symbol: "heart.fill", color: Color(red: 1.0, green: 0.23, blue: 0.36),
                              label: "HealthKit access", detail: healthKitDetail),
                        .init(symbol: "bolt.fill", color: Color(red: 1.0, green: 0.58, blue: 0.0),
                              label: "Background sync", detail: autoSyncManager.isSyncEnabled ? "On" : "Off"),
                        .init(symbol: "checkmark.shield.fill", color: Color(red: 0.20, green: 0.78, blue: 0.35),
                              label: "Demo mode", detail: useDemoData ? "On" : "Off",
                              action: { useDemoData.toggle() })
                    ])
                    .padding(.horizontal, 16)

                    SectionLabel(text: "Privacy")
                        .padding(.horizontal, 16)
                        .padding(.top, 18)

                    settingsGroup(rows: [
                        .init(symbol: "lock.shield.fill", color: Color(red: 0.07, green: 0.07, blue: 0.09),
                              label: "Where my data lives", detail: "Only here"),
                        .init(symbol: "brain.head.profile", color: Color(red: 0.75, green: 0.35, blue: 0.95),
                              label: "What the agent remembers", detail: "14 days")
                    ])
                    .padding(.horizontal, 16)

                    SectionLabel(text: "Account")
                        .padding(.horizontal, 16)
                        .padding(.top, 18)

                    signOutRow
                        .padding(.horizontal, 16)
                }
                .padding(.bottom, 130)
            }
        }
        .sheet(isPresented: $showConnectionSheet) {
            EditConnectionSheet(backend: backend, autoSyncManager: autoSyncManager)
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog(
            "Sign out and redo onboarding?",
            isPresented: $showSignOutConfirm,
            titleVisibility: .visible
        ) {
            Button("Sign out", role: .destructive, action: signOut)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You'll go back to the onboarding flow. Your name and companion settings will be pre-filled.")
        }
    }

    private var signOutRow: some View {
        Button {
            showSignOutConfirm = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(red: 1.0, green: 0.23, blue: 0.36).opacity(0.12))
                        .frame(width: 28, height: 28)
                    Image(systemName: "arrow.uturn.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(red: 0.85, green: 0.20, blue: 0.30))
                }
                Text("Sign out · redo onboarding")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 0.85, green: 0.20, blue: 0.30))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.62))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.5), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func signOut() {
        backend.disconnect()
        autoSyncManager.stopAutoSync()
        hasOnboarded = false
    }

    // MARK: - Avatar header

    private var avatarHeader: some View {
        HStack(spacing: 14) {
            JellyDisc(blur: 6, intensity: 1.0, speed: 0.9)
                .frame(width: 84, height: 84)
                .frame(width: 64, height: 64)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.1), radius: 14, y: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.09))
                Text(profileDetail)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.55))
            }

            Spacer()
        }
    }

    // MARK: - Connection card

    private var connectionCard: some View {
        Button {
            showConnectionSheet = true
        } label: {
            GlassCard(padding: 16, radius: 22) {
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        JellyDisc(blur: 4, intensity: 1.0, speed: 1.0)
                            .frame(width: 50, height: 50)
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(backend.isConnected ? "Connected to \(companionDisplayName)" : "\(companionDisplayName) offline")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.09))
                            Text("\(backend.host) : \(backend.port) · ws")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.black.opacity(0.55))
                        }

                        Spacer()

                        Text(backend.isConnected ? "LIVE" : "OFFLINE")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(0.3)
                            .foregroundStyle(backend.isConnected
                                             ? Color(red: 0.12, green: 0.48, blue: 0.24)
                                             : Color.black.opacity(0.45))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule().fill(backend.isConnected
                                               ? Color(red: 0.20, green: 0.78, blue: 0.35).opacity(0.15)
                                               : Color.black.opacity(0.06))
                            )
                    }

                    HStack {
                        Text(syncSummary)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.black.opacity(0.65))
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.black.opacity(0.04))
                    )
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var syncSummary: String {
        let status = autoSyncManager.isSyncEnabled ? "auto sync on" : "auto sync off"
        return "↑ \(status)\n↓ \(backend.statusText.lowercased())"
    }

    // MARK: - Settings rows

    private func settingsGroup(rows: [SettingRowConfig]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                SettingRowView(config: row, isLast: idx == rows.count - 1)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.62))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.5), lineWidth: 0.5)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Derived display

    private var displayName: String {
        let trimmed = userName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        if viewModel.snapshot.userProfile.isPlaceholder { return "PeerHealth user" }
        return "Your profile"
    }

    private var companionDisplayName: String {
        let raw = companionName.trimmingCharacters(in: .whitespaces)
        return raw.isEmpty ? "GX10" : raw
    }

    private var profileDetail: String {
        let p = viewModel.snapshot.userProfile
        return [p.ageDescription, p.heightDescription, p.weightDescription]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var healthKitDetail: String {
        let count = viewModel.snapshot.metrics.filter { $0.value != nil }.count
        return count > 0 ? "\(count) types" : "Not granted"
    }
}

fileprivate struct SettingRowConfig {
    let symbol: String
    let color: Color
    let label: String
    let detail: String
    var action: (() -> Void)? = nil
}

private struct SettingRowView: View {
    let config: SettingRowConfig
    let isLast: Bool

    var body: some View {
        Button {
            config.action?()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.04))
                        .frame(width: 28, height: 28)
                    Image(systemName: config.symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(config.color)
                }
                Text(config.label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.09))
                Spacer()
                Text(config.detail)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.5))
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.25))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) {
                if !isLast {
                    Rectangle()
                        .fill(Color.black.opacity(0.06))
                        .frame(height: 0.5)
                        .padding(.leading, 54)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct EditConnectionSheet: View {
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
                    Text(backend.statusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
}
