//
//  HealthAutoSyncManager.swift
//  PeerHealth
//
//  Watches HealthKit for new samples across the metric types we care about and
//  fires a single "data changed" callback. The downstream consumer rebuilds a
//  full samples bundle and POSTs it to /api/sync — we don't ship raw deltas
//  because the GX10 backend's aggregator expects {metrics, sleep, workouts, …}
//  shape rather than HealthKit-delta shape.
//

import Combine
import Foundation
import HealthKit

@MainActor
final class HealthAutoSyncManager: ObservableObject {
    @Published private(set) var isSyncEnabled = false
    @Published private(set) var statusText = "Auto sync is off."
    @Published private(set) var lastChangeAt: Date?

    private let healthStore = HKHealthStore()
    private let defaults: UserDefaults
    private var observerQueries: [HKObserverQuery] = []
    private var dataChangedHandler: (() -> Void)?
    /// Coalesces rapid bursts of observer fires into a single push.
    private var coalesceTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var sharedHealthStore: HKHealthStore { healthStore }

    /// Starts background observers. The handler is invoked (debounced) whenever
    /// any tracked sample type sees new or deleted samples since the last anchor.
    func startAutoSync(onDataChanged: @escaping () -> Void) async {
        guard HKHealthStore.isHealthDataAvailable() else {
            statusText = "Health data is unavailable on this device."
            return
        }

        dataChangedHandler = onDataChanged

        do {
            try await healthStore.requestAuthorization(toShare: [], read: Set(Self.observedSampleTypes))
        } catch {
            statusText = "HealthKit authorization failed: \(error.localizedDescription)"
            return
        }

        stopQueriesOnly()

        for sampleType in Self.observedSampleTypes {
            registerObserver(for: sampleType)
            await enableBackgroundDelivery(for: sampleType)
            await pullIncrementalUpdates(for: sampleType)
        }

        isSyncEnabled = true
        statusText = "Auto sync is active."
    }

    func stopAutoSync() {
        stopQueriesOnly()
        coalesceTask?.cancel()
        coalesceTask = nil
        dataChangedHandler = nil
        isSyncEnabled = false
        statusText = "Auto sync is off."
    }
}

private extension HealthAutoSyncManager {

    static var observedSampleTypes: [HKSampleType] {
        [
            HKObjectType.quantityType(forIdentifier: .heartRate),
            HKObjectType.quantityType(forIdentifier: .restingHeartRate),
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
            HKObjectType.quantityType(forIdentifier: .stepCount),
            HKObjectType.quantityType(forIdentifier: .respiratoryRate),
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
            HKObjectType.workoutType()
        ]
        .compactMap { $0 }
    }

    func registerObserver(for sampleType: HKSampleType) {
        let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { [weak self] _, completion, error in
            guard let self else {
                completion()
                return
            }

            if let error {
                Task { @MainActor in
                    self.statusText = "Observer error (\(sampleType.identifier)): \(error.localizedDescription)"
                }
                completion()
                return
            }

            Task { @MainActor in
                await self.pullIncrementalUpdates(for: sampleType)
                completion()
            }
        }

        observerQueries.append(query)
        healthStore.execute(query)
    }

    func stopQueriesOnly() {
        for query in observerQueries {
            healthStore.stop(query)
        }
        observerQueries.removeAll()
    }

    func enableBackgroundDelivery(for sampleType: HKSampleType) async {
        await withCheckedContinuation { continuation in
            healthStore.enableBackgroundDelivery(for: sampleType, frequency: .immediate) { _, _ in
                continuation.resume()
            }
        }
    }

    func pullIncrementalUpdates(for sampleType: HKSampleType) async {
        let anchor = loadAnchor(for: sampleType.identifier)

        await withCheckedContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: sampleType,
                predicate: nil,
                anchor: anchor,
                limit: HKObjectQueryNoLimit
            ) { [weak self] _, addedSamples, deletedObjects, newAnchor, error in
                guard let self else {
                    continuation.resume()
                    return
                }

                Task { @MainActor [self] in
                    if let error {
                        self.statusText = "Sync failed (\(sampleType.identifier)): \(error.localizedDescription)"
                        continuation.resume()
                        return
                    }

                    if let newAnchor {
                        self.saveAnchor(newAnchor, for: sampleType.identifier)
                    }

                    let added = addedSamples?.count ?? 0
                    let deleted = deletedObjects?.count ?? 0
                    if added > 0 || deleted > 0 {
                        self.lastChangeAt = Date()
                        self.statusText = "\(sampleType.identifier) +\(added)/-\(deleted)"
                        self.scheduleCoalescedPush()
                    }

                    continuation.resume()
                }
            }

            healthStore.execute(query)
        }
    }

    /// Many sample types can fire observers within the same second — collapse
    /// them into a single bundle build + push.
    func scheduleCoalescedPush() {
        coalesceTask?.cancel()
        coalesceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.dataChangedHandler?()
            }
        }
    }

    func anchorKey(for identifier: String) -> String {
        "health.anchor.\(identifier)"
    }

    func loadAnchor(for identifier: String) -> HKQueryAnchor? {
        guard let data = defaults.data(forKey: anchorKey(for: identifier)) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    func saveAnchor(_ anchor: HKQueryAnchor, for identifier: String) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true) else {
            return
        }
        defaults.set(data, forKey: anchorKey(for: identifier))
    }
}
