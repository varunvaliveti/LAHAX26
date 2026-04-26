//
//  HealthAutoSyncManager.swift
//  PeerHealth
//

import Combine
import Foundation
import HealthKit

@MainActor
final class HealthAutoSyncManager: ObservableObject {
    @Published private(set) var isSyncEnabled = false
    @Published private(set) var statusText = "Auto sync is off."

    private let healthStore = HKHealthStore()
    private let defaults: UserDefaults
    private var observerQueries: [HKObserverQuery] = []
    private var outboundHandler: ((String) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func startAutoSync(onPayload: @escaping (String) -> Void) async {
        guard HKHealthStore.isHealthDataAvailable() else {
            statusText = "Health data is unavailable on this device."
            return
        }

        outboundHandler = onPayload

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
        outboundHandler = nil
        isSyncEnabled = false
        statusText = "Auto sync is off."
    }
}

private extension HealthAutoSyncManager {
    struct SyncPayload: Codable {
        let source: String
        let generatedAt: String
        let sampleType: String
        let added: [AddedSample]
        let deletedUUIDs: [String]
    }

    struct AddedSample: Codable {
        let uuid: String
        let startDate: String
        let endDate: String
        let value: Double?
        let unit: String?
        let categoryValue: Int?
    }

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

                    let payload = self.makePayload(
                        sampleType: sampleType,
                        addedSamples: addedSamples ?? [],
                        deletedObjects: deletedObjects ?? []
                    )

                    if let payload {
                        self.outboundHandler?(payload)
                        self.statusText = "Synced \(sampleType.identifier) update."
                    }

                    continuation.resume()
                }
            }

            healthStore.execute(query)
        }
    }

    func makePayload(
        sampleType: HKSampleType,
        addedSamples: [HKSample],
        deletedObjects: [HKDeletedObject]
    ) -> String? {
        guard !addedSamples.isEmpty || !deletedObjects.isEmpty else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        let added = addedSamples.map { sample -> AddedSample in
            if let quantity = sample as? HKQuantitySample {
                let resolved = resolvedUnit(for: sampleType.identifier)
                return AddedSample(
                    uuid: quantity.uuid.uuidString,
                    startDate: formatter.string(from: quantity.startDate),
                    endDate: formatter.string(from: quantity.endDate),
                    value: quantity.quantity.doubleValue(for: resolved.unit),
                    unit: resolved.unitLabel,
                    categoryValue: nil
                )
            }

            if let category = sample as? HKCategorySample {
                return AddedSample(
                    uuid: category.uuid.uuidString,
                    startDate: formatter.string(from: category.startDate),
                    endDate: formatter.string(from: category.endDate),
                    value: nil,
                    unit: nil,
                    categoryValue: category.value
                )
            }

            if let workout = sample as? HKWorkout {
                return AddedSample(
                    uuid: workout.uuid.uuidString,
                    startDate: formatter.string(from: workout.startDate),
                    endDate: formatter.string(from: workout.endDate),
                    value: workout.duration / 60.0,
                    unit: "min",
                    categoryValue: nil
                )
            }

            return AddedSample(
                uuid: sample.uuid.uuidString,
                startDate: formatter.string(from: sample.startDate),
                endDate: formatter.string(from: sample.endDate),
                value: nil,
                unit: nil,
                categoryValue: nil
            )
        }

        let payload = SyncPayload(
            source: "healthkit_auto_sync",
            generatedAt: formatter.string(from: Date()),
            sampleType: sampleType.identifier,
            added: added,
            deletedUUIDs: deletedObjects.map { $0.uuid.uuidString }
        )

        let encoder = JSONEncoder()
        guard let encoded = try? encoder.encode(payload) else { return nil }
        return String(data: encoded, encoding: .utf8)
    }

    func resolvedUnit(for identifier: String) -> (unit: HKUnit, unitLabel: String) {
        switch identifier {
        case HKQuantityTypeIdentifier.heartRate.rawValue,
             HKQuantityTypeIdentifier.restingHeartRate.rawValue,
             HKQuantityTypeIdentifier.respiratoryRate.rawValue:
            return (HKUnit.count().unitDivided(by: .minute()), "count/min")
        case HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue:
            return (.secondUnit(with: .milli), "ms")
        case HKQuantityTypeIdentifier.stepCount.rawValue:
            return (.count(), "count")
        default:
            return (.count(), "count")
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
