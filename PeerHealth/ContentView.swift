//
//  ContentView.swift
//  PeerHealth
//
//  Created by Varun Valiveti on 4/25/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = HealthDashboardViewModel()
    @StateObject private var tcpConnectionManager = TCPConnectionManager()
    @StateObject private var healthAutoSyncManager = HealthAutoSyncManager()
    @State private var selectedTab: PHTab = .home
    @AppStorage("peerHealthUseDemoData") private var useDemoData = false
    @AppStorage("peerHealthHasOnboarded") private var hasOnboarded = false
    @AppStorage("peerHealthHost") private var storedHost = "10.30.77.124"

    var body: some View {
        Group {
            if hasOnboarded {
                mainTabs
            } else {
                OnboardingScreen()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: hasOnboarded)
    }

    private var mainTabs: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case .home:
                    HomeScreen(viewModel: viewModel,
                               connectionManager: tcpConnectionManager,
                               useDemoData: useDemoData)
                case .insights:
                    InsightsScreen(viewModel: viewModel, useDemoData: useDemoData)
                case .chat:
                    ChatScreen(connectionManager: tcpConnectionManager,
                               autoSyncManager: healthAutoSyncManager)
                case .profile:
                    ProfileScreen(viewModel: viewModel,
                                  connectionManager: tcpConnectionManager,
                                  autoSyncManager: healthAutoSyncManager,
                                  useDemoData: $useDemoData)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            PHTabBar(selected: $selectedTab)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .task {
            if tcpConnectionManager.host != storedHost {
                tcpConnectionManager.host = storedHost
            }
            await viewModel.bootstrap(useSimulation: useDemoData)
        }
        .onChange(of: useDemoData) { _, new in
            Task { await viewModel.bootstrap(useSimulation: new) }
        }
        .onChange(of: storedHost) { _, new in
            tcpConnectionManager.host = new
        }
    }
}

#Preview {
    ContentView()
}
