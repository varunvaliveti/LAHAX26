//
//  HealthDashboardViewModel.swift
//  PeerHealth
//

import Combine
import Foundation
import HealthKit

struct HealthMetric: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let value: Double
    let unit: String
    let summary: String

    var formattedValue: String {
        if value.rounded() == value {
            return "\(Int(value)) \(unit)"
        }

        return String(format: "%.1f %@", value, unit)
    }
}

struct HealthSnapshot: Equatable {
    let source: String
    let generatedAt: Date
    let metrics: [HealthMetric]

    var payloadPreview: String {
        let formatter = ISO8601DateFormatter()
        let entries = metrics.map { metric in
            """
              {
                "name": "\(metric.title)",
                "value": \(String(format: "%.2f", metric.value)),
                "unit": "\(metric.unit)"
              }
            """
        }
        .joined(separator: ",\n")

        return """
        {
          "source": "\(source)",
          "generatedAt": "\(formatter.string(from: generatedAt))",
          "metrics": [
        \(entries)
          ]
        }
        """
    }

    static let placeholder = HealthSnapshot(
        source: "simulation",
        generatedAt: .now,
        metrics: [
            HealthMetric(title: "Resting Heart Rate", value: 58, unit: "bpm", summary: "Baseline nighttime recovery marker."),
            HealthMetric(title: "Heart Rate Variability", value: 42, unit: "ms", summary: "Higher values generally reflect better recovery."),
            HealthMetric(title: "Respiratory Rate", value: 14.5, unit: "br/min", summary: "Useful for spotting stress or illness patterns."),
            HealthMetric(title: "Step Count", value: 8412, unit: "steps", summary: "Daily movement volume from wearable sensors."),
            HealthMetric(title: "Sleep Duration", value: 7.4, unit: "hrs", summary: "Last overnight sleep window from tracker samples.")
        ]
    )
}

@MainActor
final class HealthDashboardViewModel: ObservableObject {
    @Published private(set) var snapshot: HealthSnapshot = .placeholder
    @Published private(set) var statusMessage = "Simulation is enabled for the hackathon flow."

    private let healthStore = HKHealthStore()

    var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() async {
        guard isHealthDataAvailable else {
            statusMessage = "Health data is not available on this device."
            return
        }

        do {
            try await healthStore.requestAuthorization(toShare: [], read: HealthDashboardViewModel.requiredTypes)
            statusMessage = "HealthKit authorization granted. Pulling the latest metrics."
        } catch {
            statusMessage = "HealthKit authorization failed: \(error.localizedDescription)"
        }
    }

    func loadMetrics(useSimulation: Bool) async {
        if useSimulation {
            snapshot = Self.makeSimulatedSnapshot()
            statusMessage = "Showing simulated HealthKit-style data for the demo."
            return
        }

        guard isHealthDataAvailable else {
            snapshot = Self.makeSimulatedSnapshot()
            statusMessage = "HealthKit is unavailable here, so the app fell back to simulation."
            return
        }

        do {
            snapshot = try await fetchHealthKitSnapshot()
            statusMessage = "Imported the latest HealthKit metrics."
        } catch {
            snapshot = Self.makeSimulatedSnapshot()
            statusMessage = "HealthKit import failed, so the app fell back to simulation."
        }
    }
}

private extension HealthDashboardViewModel {
    static var requiredTypes: Set<HKObjectType> {
        [
            HKObjectType.quantityType(forIdentifier: .restingHeartRate),
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
            HKObjectType.quantityType(forIdentifier: .respiratoryRate),
            HKObjectType.quantityType(forIdentifier: .stepCount),
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        ]
        .compactMap { $0 }
        .reduce(into: Set<HKObjectType>()) { result, type in
            result.insert(type)
        }
    }

    static func makeSimulatedSnapshot() -> HealthSnapshot {
        HealthSnapshot(
            source: "simulation",
            generatedAt: .now,
            metrics: [
                HealthMetric(title: "Resting Heart Rate", value: Double.random(in: 56...67), unit: "bpm", summary: "Nighttime resting heart rate for recovery tracking."),
                HealthMetric(title: "Heart Rate Variability", value: Double.random(in: 28...61), unit: "ms", summary: "HRV trend for stress and recovery interpretation."),
                HealthMetric(title: "Respiratory Rate", value: Double.random(in: 12.8...17.4), unit: "br/min", summary: "Overnight breathing rate trend from wearable data."),
                HealthMetric(title: "Step Count", value: Double(Int.random(in: 4300...12400)), unit: "steps", summary: "Daily movement volume aggregated across devices."),
                HealthMetric(title: "Sleep Duration", value: Double.random(in: 6.1...8.4), unit: "hrs", summary: "Last overnight sleep estimate for the demo agent.")
            ]
        )
    }

    func fetchHealthKitSnapshot() async throws -> HealthSnapshot {
        async let restingHeartRate = latestQuantitySample(
            typeIdentifier: .restingHeartRate,
            unit: HKUnit.count().unitDivided(by: .minute())
        )
        async let hrv = latestQuantitySample(
            typeIdentifier: .heartRateVariabilitySDNN,
            unit: .secondUnit(with: .milli)
        )
        async let respiratoryRate = latestQuantitySample(
            typeIdentifier: .respiratoryRate,
            unit: HKUnit.count().unitDivided(by: .minute())
        )
        async let stepCount = cumulativeQuantitySample(
            typeIdentifier: .stepCount,
            unit: .count(),
            startDate: Calendar.current.startOfDay(for: .now),
            endDate: .now
        )
        async let sleepDuration = sleepHoursForLast24Hours()

        let metrics = try await [
            HealthMetric(
                title: "Resting Heart Rate",
                value: restingHeartRate,
                unit: "bpm",
                summary: "Latest resting heart rate imported from HealthKit."
            ),
            HealthMetric(
                title: "Heart Rate Variability",
                value: hrv,
                unit: "ms",
                summary: "Latest HRV (SDNN) sample imported from HealthKit."
            ),
            HealthMetric(
                title: "Respiratory Rate",
                value: respiratoryRate,
                unit: "br/min",
                summary: "Latest respiratory rate sample from HealthKit."
            ),
            HealthMetric(
                title: "Step Count",
                value: stepCount,
                unit: "steps",
                summary: "Total steps recorded since the start of today."
            ),
            HealthMetric(
                title: "Sleep Duration",
                value: sleepDuration,
                unit: "hrs",
                summary: "Total asleep time over the last 24 hours."
            )
        ]

        return HealthSnapshot(source: "healthkit", generatedAt: .now, metrics: metrics)
    }

    func latestQuantitySample(typeIdentifier: HKQuantityTypeIdentifier, unit: HKUnit) async throws -> Double {
        guard let sampleType = HKObjectType.quantityType(forIdentifier: typeIdentifier) else {
            throw HealthDashboardError.unsupportedType
        }

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sampleType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let quantitySample = samples?.first as? HKQuantitySample else {
                    continuation.resume(throwing: HealthDashboardError.noSamples)
                    return
                }

                continuation.resume(returning: quantitySample.quantity.doubleValue(for: unit))
            }

            healthStore.execute(query)
        }
    }

    func cumulativeQuantitySample(
        typeIdentifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        startDate: Date,
        endDate: Date
    ) async throws -> Double {
        guard let sampleType = HKObjectType.quantityType(forIdentifier: typeIdentifier) else {
            throw HealthDashboardError.unsupportedType
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: sampleType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let value = result?.sumQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: value)
            }

            healthStore.execute(query)
        }
    }

    func sleepHoursForLast24Hours() async throws -> Double {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw HealthDashboardError.unsupportedType
        }

        let startDate = Calendar.current.date(byAdding: .hour, value: -24, to: .now) ?? .now.addingTimeInterval(-86_400)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: .now)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let totalSeconds = (samples as? [HKCategorySample] ?? []).reduce(0.0) { total, sample in
                    guard Self.isAsleep(sample) else { return total }
                    return total + sample.endDate.timeIntervalSince(sample.startDate)
                }

                continuation.resume(returning: totalSeconds / 3600)
            }

            healthStore.execute(query)
        }
    }

    nonisolated static func isAsleep(_ sample: HKCategorySample) -> Bool {
        switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
        case .inBed, .awake:
            return false
        case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM:
            return true
        case nil:
            return false
        @unknown default:
            return true
        }
    }
}

enum HealthDashboardError: Error {
    case noSamples
    case unsupportedType
}
