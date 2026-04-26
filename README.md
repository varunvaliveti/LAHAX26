# PeerHealth

PeerHealth is an iOS SwiftUI app that reads Apple Health data, generates lightweight on-device insights, and can sync updates to a remote peer/agent over TCP (for example, an Asus GX10 box on the same network).

## What It Does

- Displays a health dashboard with metrics like resting HR, HRV, sleep, steps, workouts, and more.
- Supports two data modes:
  - **HealthKit mode**: reads real Apple Health data from the device.
  - **Demo mode**: generates simulated data for simulator/testing use.
- Includes a chat-style screen for sending messages to a TCP endpoint.
- Provides optional **HealthKit auto sync** that watches for new Health samples and forwards incremental JSON payloads over TCP when connected.

## App Structure

- `PeerHealth/PeerHealthApp.swift` - app entry point.
- `PeerHealth/ContentView.swift` - main tab UI (`Home`, `Chat`, `Profile`).
- `PeerHealth/HealthDashboardViewModel.swift` - HealthKit authorization, metric queries, snapshot modeling, and demo snapshot generation.
- `PeerHealth/HealthAutoSyncManager.swift` - anchored HealthKit observer queries and incremental payload generation.
- `PeerHealth/TCPConnectionManager.swift` - TCP connect/send/receive logic using `Network`.

## Requirements

- Xcode 15+ (recommended)
- iOS 17+ target device/simulator
- Apple developer signing configured for running on a real device
- Health permissions enabled in app capabilities (`PeerHealth.entitlements` is included)

## Run Locally

1. Open `PeerHealth.xcodeproj` in Xcode.
2. Select an iOS simulator or physical device.
3. Build and run.

### Using Real Health Data

1. Run on a device with Apple Health data available.
2. Grant requested Health permissions when prompted.
3. Pull to refresh on the Home tab to reload metrics.

### Using Demo Data

1. Open the `Profile` tab.
2. Enable **Use demo health data (no HealthKit)**.
3. Return to `Home` to view simulated metrics and insights.

## TCP Chat + Auto Sync

In the `Chat` tab:

1. Enter target host and port.
2. Tap **Connect** to establish TCP session.
3. Send chat messages from the input field.
4. Optional: tap **Start Auto Sync** to watch HealthKit changes and forward incremental payloads.

Auto sync payloads include:

- sample type identifier
- added sample entries (with value/unit when applicable)
- deleted sample UUIDs
- ISO-8601 timestamps

## Notes

- Simulator HealthKit data can be limited; demo mode is useful for UI and flow testing.
- If no Health data is found, the app shows empty/placeholder states and guidance text.
- Network communication currently uses plain TCP and should be used on trusted networks for development.

## Tests

The project includes default test targets:

- `PeerHealthTests`
- `PeerHealthUITests`

Run with Xcode test action (`Product > Test`) or `Cmd+U`.
