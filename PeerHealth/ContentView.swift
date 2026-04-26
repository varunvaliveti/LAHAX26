//
//  ContentView.swift
//  PeerHealth
//
//  Created by Varun Valiveti on 4/25/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = HealthDashboardViewModel()
    @StateObject private var backendClient = BackendClient()
    @StateObject private var healthAutoSyncManager = HealthAutoSyncManager()
    @State private var selectedTab: PHTab = .home
    @AppStorage("peerHealthUseDemoData") private var useDemoData = false
    @AppStorage("peerHealthHasOnboarded") private var hasOnboarded = false
    @Environment(\.scenePhase) private var scenePhase

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
                               backend: backendClient,
                               useDemoData: useDemoData)
                case .network:
                    NetworkScreen(backend: backendClient)
                case .chat:
                    ChatScreen(backend: backendClient,
                               autoSyncManager: healthAutoSyncManager)
                case .profile:
                    ProfileScreen(viewModel: viewModel,
                                  backend: backendClient,
                                  autoSyncManager: healthAutoSyncManager,
                                  useDemoData: $useDemoData)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            PHTabBar(selected: $selectedTab)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .task {
            await viewModel.bootstrap(useSimulation: useDemoData)
            backendClient.refreshFromDefaults()
            backendClient.connect()
            await healthAutoSyncManager.startAutoSync { [weak backendClient, weak healthAutoSyncManager] in
                guard let backendClient, let healthAutoSyncManager else { return }
                Task { @MainActor in
                    let bundle = await SamplesBundleBuilder.build(store: healthAutoSyncManager.sharedHealthStore)
                    await backendClient.pushHealthData(samples: bundle)
                }
            }
            // Initial push so the backend has something to aggregate even if no
            // observer fires in the first session.
            let bundle = await SamplesBundleBuilder.build(store: healthAutoSyncManager.sharedHealthStore)
            await backendClient.pushHealthData(samples: bundle)
        }
        .onChange(of: useDemoData) { _, new in
            Task { await viewModel.bootstrap(useSimulation: new) }
        }
        .onChange(of: scenePhase) { _, new in
            if new == .active {
                backendClient.ensureConnected()
            }
        }
    }
}

#Preview {
    ContentView()
}
