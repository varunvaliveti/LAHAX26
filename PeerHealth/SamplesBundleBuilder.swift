//
//  SamplesBundleBuilder.swift
//  PeerHealth
//
//  Builds the {metrics, workouts, sleep, notes, profile, timestamp} payload
//  that backend/store/data.py:aggregate_7_day_summary expects, by reading
//  raw HealthKit samples for a lookback window.
//
//  NOTE: the inner key names below are a best guess pending confirmation
//  against the backend's ingest schema. If aggregate_7_day_summary returns
//  "No data on file" after a sync, the keys here are the place to start.
//

import Foundation
import HealthKit

@MainActor
enum SamplesBundleBuilder {

    /// Build a samples bundle for the given lookback window (default 30 days).
    /// `regionHint` is optional and will be carried into `profile.region` if non-empty.
    static func build(
        store: HKHealthStore,
        lookbackDays: Int = 30,
        regionHint: String? = nil
    ) async -> [String: Any] {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        let now = Date()
        let from = Calendar.current.date(byAdding: .day, value: -lookbackDays, to: now) ?? now

        async let rhr   = quantitySamples(store: store, .restingHeartRate,
                                          unit: HKUnit.count().unitDivided(by: .minute()),
                                          from: from, to: now)
        async let hrv   = quantitySamples(store: store, .heartRateVariabilitySDNN,
                                          unit: .secondUnit(with: .milli),
                                          from: from, to: now)
        async let hr    = quantitySamples(store: store, .heartRate,
                                          unit: HKUnit.count().unitDivided(by: .minute()),
                                          from: from, to: now)
        async let resp  = quantitySamples(store: store, .respiratoryRate,
                                          unit: HKUnit.count().unitDivided(by: .minute()),
                                          from: from, to: now)
        async let steps = quantitySamples(store: store, .stepCount,
                                          unit: .count(),
                                          from: from, to: now)
        async let sleep    = sleepIntervals(store: store, from: from, to: now)
        async let workouts = workoutSamples(store: store, from: from, to: now)
        async let height   = latestQuantity(store: store, .height,
                                            unit: .meter())
        async let weight   = latestQuantity(store: store, .bodyMass,
                                            unit: HKUnit.gramUnit(with: .kilo))

        let rRhr   = await rhr
        let rHrv   = await hrv
        let rHr    = await hr
        let rResp  = await resp
        let rSteps = await steps
        let rSleep = await sleep
        let rWk    = await workouts
        let rH     = await height
        let rW     = await weight

        var profile: [String: Any] = [:]

        if let dob = try? store.dateOfBirthComponents().date {
            let years = Calendar.current.dateComponents([.year], from: dob, to: now).year ?? 0
            if years > 0 { profile["age"] = years }
        }

        if let sex = try? store.biologicalSex() {
            switch sex.biologicalSex {
            case .male:   profile["sex"] = "M"
            case .female: profile["sex"] = "F"
            case .other:  profile["sex"] = "O"
            case .notSet: break
            @unknown default: break
            }
        }

        if let h = rH { profile["height_cm"] = (h * 100).rounded() / 1 }
        if let w = rW { profile["weight_kg"] = (w * 10).rounded() / 10 }

        let region = (regionHint?.isEmpty == false) ? regionHint! : (Locale.current.region?.identifier ?? "")
        if !region.isEmpty { profile["region"] = region }

        let metrics: [String: Any] = [
            "rhr":   rRhr.map  { ["value": $0.value, "timestamp": iso.string(from: $0.endDate)] },
            "hrv":   rHrv.map  { ["value": $0.value, "timestamp": iso.string(from: $0.endDate)] },
            "hr":    rHr.map   { ["value": $0.value, "timestamp": iso.string(from: $0.endDate)] },
            "resp":  rResp.map { ["value": $0.value, "timestamp": iso.string(from: $0.endDate)] },
            "steps": rSteps.map{ ["value": $0.value, "timestamp": iso.string(from: $0.endDate)] }
        ]

        let sleepArr: [[String: Any]] = rSleep.map { interval in
            [
                "start": iso.string(from: interval.start),
                "end":   iso.string(from: interval.end),
                "hours": (interval.end.timeIntervalSince(interval.start) / 3600.0)
            ]
        }

        let workoutsArr: [[String: Any]] = rWk.map { w in
            [
                "type": w.type,
                "duration_min": w.durationMinutes,
                "start": iso.string(from: w.start),
                "end":   iso.string(from: w.end)
            ]
        }

        return [
            "timestamp": iso.string(from: now),
            "profile":   profile,
            "metrics":   metrics,
            "sleep":     sleepArr,
            "workouts":  workoutsArr,
            "notes":     ""
        ]
    }
}

// MARK: - Internal helpers

private struct ValueAt {
    let value: Double
    let endDate: Date
}

private struct SleepInterval {
    let start: Date
    let end: Date
}

private struct WorkoutEntry {
    let type: String
    let durationMinutes: Double
    let start: Date
    let end: Date
}

@MainActor
private extension SamplesBundleBuilder {

    static func quantitySamples(
        store: HKHealthStore,
        _ id: HKQuantityTypeIdentifier,
        unit: HKUnit,
        from: Date,
        to: Date
    ) async -> [ValueAt] {
        await withCheckedContinuation { cont in
            guard let t = HKObjectType.quantityType(forIdentifier: id) else {
                cont.resume(returning: [])
                return
            }
            let predicate = HKQuery.predicateForSamples(withStart: from, end: to)
            let sort = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)]
            let q = HKSampleQuery(
                sampleType: t,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: sort
            ) { _, samples, _ in
                let out: [ValueAt] = (samples as? [HKQuantitySample] ?? []).map {
                    ValueAt(value: $0.quantity.doubleValue(for: unit), endDate: $0.endDate)
                }
                cont.resume(returning: out)
            }
            store.execute(q)
        }
    }

    static func latestQuantity(
        store: HKHealthStore,
        _ id: HKQuantityTypeIdentifier,
        unit: HKUnit
    ) async -> Double? {
        await withCheckedContinuation { cont in
            guard let t = HKObjectType.quantityType(forIdentifier: id) else {
                cont.resume(returning: nil)
                return
            }
            let sort = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            let q = HKSampleQuery(
                sampleType: t,
                predicate: nil,
                limit: 1,
                sortDescriptors: sort
            ) { _, samples, _ in
                let v = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                cont.resume(returning: v)
            }
            store.execute(q)
        }
    }

    static func sleepIntervals(
        store: HKHealthStore,
        from: Date,
        to: Date
    ) async -> [SleepInterval] {
        await withCheckedContinuation { cont in
            guard let t = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
                cont.resume(returning: [])
                return
            }
            let predicate = HKQuery.predicateForSamples(withStart: from, end: to)
            let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            let q = HKSampleQuery(
                sampleType: t,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: sort
            ) { _, samples, _ in
                let out: [SleepInterval] = (samples as? [HKCategorySample] ?? [])
                    .filter { isAsleep($0) }
                    .map { SleepInterval(start: $0.startDate, end: $0.endDate) }
                cont.resume(returning: out)
            }
            store.execute(q)
        }
    }

    static func workoutSamples(
        store: HKHealthStore,
        from: Date,
        to: Date
    ) async -> [WorkoutEntry] {
        await withCheckedContinuation { cont in
            let predicate = HKQuery.predicateForSamples(withStart: from, end: to)
            let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            let q = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: sort
            ) { _, samples, _ in
                let out: [WorkoutEntry] = (samples as? [HKWorkout] ?? []).map {
                    WorkoutEntry(
                        type: workoutTypeName($0.workoutActivityType),
                        durationMinutes: $0.duration / 60.0,
                        start: $0.startDate,
                        end: $0.endDate
                    )
                }
                cont.resume(returning: out)
            }
            store.execute(q)
        }
    }

    nonisolated static func isAsleep(_ sample: HKCategorySample) -> Bool {
        switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
        case .inBed, .awake: return false
        case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM: return true
        case nil: return false
        @unknown default: return true
        }
    }

    nonisolated static func workoutTypeName(_ t: HKWorkoutActivityType) -> String {
        switch t {
        case .running: return "Running"
        case .walking: return "Walking"
        case .cycling: return "Cycling"
        case .hiking:  return "Hiking"
        case .swimming: return "Swimming"
        case .yoga:    return "Yoga"
        case .functionalStrengthTraining, .traditionalStrengthTraining: return "Strength"
        case .highIntensityIntervalTraining: return "HIIT"
        case .rowing:  return "Rowing"
        case .elliptical: return "Elliptical"
        case .stairClimbing: return "Stairs"
        case .pilates: return "Pilates"
        case .dance:   return "Dance"
        case .tennis:  return "Tennis"
        case .basketball: return "Basketball"
        case .soccer:  return "Soccer"
        case .climbing: return "Climbing"
        case .crossTraining: return "Cross-training"
        default:       return "Workout"
        }
    }
}
