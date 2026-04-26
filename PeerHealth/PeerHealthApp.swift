//
//  PeerHealthApp.swift
//  PeerHealth
//
//  Created by Varun Valiveti on 4/25/26.
//

import SwiftUI

@main
struct PeerHealthApp: App {
    init() {
        Self.migrateLegacyDefaults()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }

    /// One-shot rewrite of values written by older builds so we don't keep
    /// connecting to dead endpoints from a previous IP.
    private static func migrateLegacyDefaults() {
        let legacyHosts: Set<String> = ["10.30.77.124"]
        let key = "peerHealthHost"
        if let stored = UserDefaults.standard.string(forKey: key),
           legacyHosts.contains(stored) {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
