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
    let value: Double?
    let unit: String
    let summary: String

    var formattedValue: String {
        guard let value else { return "—" }
        if value.rounded() == value {
            return "\(Int(value)) \(unit)"
        }
        return String(format: "%.1f %@", value, unit)
    }
}

struct DaySleepPoint: Equatable {
    let weekdayLabel: String
    let hours: Double?
}

struct UserHealthProfile: Equatable {
    var ageDescription: String
    var sexDescription: String
    var heightDescription: String
    var weightDescription: String
    var isPlaceholder: Bool
}

struct HealthSnapshot: Equatable {
    let source: String
    let generatedAt: Date
    let metrics: [HealthMetric]
    let weekSleep: [DaySleepPoint]
    let heartRateLineNormalizedYs: [CGFloat]
    let userProfile: UserHealthProfile

    var averageSleepThisWeek: Double? {
        let values = weekSleep.compactMap(\.hours)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var payloadPreview: String {
        let formatter = ISO8601DateFormatter()
        let entries = metrics.map { metric in
            let valuePart: String
            if let v = metric.value {
                valuePart = String(format: "%.2f", v)
            } else {
                valuePart = "null"
            }
            return """
              {
                "name": "\(metric.title)",
                "value": \(valuePart),
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
            HealthMetric(title: "Sleep (last 24h asleep)", value: 7.4, unit: "hrs", summary: "Last overnight sleep window from tracker samples.")
        ],
        weekSleep: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"].map {
            DaySleepPoint(weekdayLabel: $0, hours: 7.0)
        },
        heartRateLineNormalizedYs: [0.72, 0.44, 0.53, 0.38, 0.66],
        userProfile: .demo
    )
}

private extension UserHealthProfile {
    static var demo: UserHealthProfile {
        UserHealthProfile(
            ageDescription: "40-44 (demo)",
            sexDescription: "Not set",
            heightDescription: "5′11″",
            weightDescription: "178 lb",
            isPlaceholder: true
        )
    }
}

@MainActor
final class HealthDashboardViewModel: ObservableObject {
    @Published private(set) var snapshot: HealthSnapshot = .placeholder
    @Published private(set) var statusMessage = "Connect Apple Health to load your data."

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
            try await healthStore.requestAuthorization(toShare: [], read: Self.readObjectTypes)
            statusMessage = "Health data access was requested. Loading metrics from HealthKit."
        } catch {
            statusMessage = "HealthKit authorization failed: \(error.localizedDescription)"
        }
    }

    /// Prefer HealthKit on device; use simulation when unavailable or for previews.
    func bootstrap() async {
        await bootstrap(useSimulation: !isHealthDataAvailable)
    }

    func bootstrap(useSimulation: Bool) async {
        if useSimulation {
            snapshot = Self.makeSimulatedFullSnapshot()
            statusMessage = "Demo mode: showing simulated health data."
            return
        }
        guard isHealthDataAvailable else {
            snapshot = Self.makeSimulatedFullSnapshot()
            statusMessage = "HealthKit is unavailable. Using demo data."
            return
        }
        await requestAuthorization()
        await loadFromHealthKit()
    }

    func setDemoMode(_ enabled: Bool) async {
        if enabled {
            await bootstrap(useSimulation: true)
        } else {
            await bootstrap(useSimulation: false)
        }
    }

    private func loadFromHealthKit() async {
        let result = await fetchHealthKitSnapshot()
        snapshot = result.snapshot
        statusMessage = result.userMessage
    }
}

// MARK: - Read types and ingestion

private extension HealthDashboardViewModel {
    static var readObjectTypes: Set<HKObjectType> {
        var set = Set<HKObjectType>()
        let quantityIDs: [HKQuantityTypeIdentifier] = [
            .restingHeartRate,
            .heartRateVariabilitySDNN,
            .heartRate,
            .respiratoryRate,
            .stepCount,
            .activeEnergyBurned,
            .appleExerciseTime,
            .appleStandTime,
            .distanceWalkingRunning,
            .flightsClimbed,
            .walkingHeartRateAverage,
            .oxygenSaturation,
            .vo2Max,
            .bodyMass,
            .height,
            .bodyMassIndex,
            .bloodPressureSystolic,
            .bloodPressureDiastolic,
            .leanBodyMass,
            .bodyFatPercentage
        ]
        for id in quantityIDs {
            if let t = HKObjectType.quantityType(forIdentifier: id) {
                set.insert(t)
            }
        }
        if let t = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            set.insert(t)
        }
        if let t = HKObjectType.categoryType(forIdentifier: .mindfulSession) {
            set.insert(t)
        }
        set.insert(HKObjectType.workoutType())
        for cid: HKCharacteristicTypeIdentifier in [.dateOfBirth, .biologicalSex, .bloodType] {
            if let t = HKObjectType.characteristicType(forIdentifier: cid) {
                set.insert(t)
            }
        }
        return set
    }

    struct FetchOutcome {
        let snapshot: HealthSnapshot
        let userMessage: String
    }

    func fetchHealthKitSnapshot() async -> FetchOutcome {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)

        async let resting = optionalLatest(
            .restingHeartRate,
            unit: HKUnit.count().unitDivided(by: .minute())
        )
        async let hrv = optionalLatest(
            .heartRateVariabilitySDNN,
            unit: .secondUnit(with: .milli)
        )
        async let respiratory = optionalLatest(
            .respiratoryRate,
            unit: HKUnit.count().unitDivided(by: .minute())
        )
        async let steps = optionalCumulative(.stepCount, unit: .count(), from: startOfToday, to: now)
        async let activeCal = optionalCumulative(
            .activeEnergyBurned,
            unit: .largeCalorie(),
            from: startOfToday,
            to: now
        )
        async let exerciseMin = optionalCumulative(
            .appleExerciseTime,
            unit: .minute(),
            from: startOfToday,
            to: now
        )
        async let standHours = optionalCumulative(
            .appleStandTime,
            unit: .count(),
            from: startOfToday,
            to: now
        )
        async let distanceM = optionalCumulative(
            .distanceWalkingRunning,
            unit: .meter(),
            from: startOfToday,
            to: now
        )
        async let flights = optionalCumulative(
            .flightsClimbed,
            unit: .count(),
            from: startOfToday,
            to: now
        )
        async let walkHR = optionalLatest(
            .walkingHeartRateAverage,
            unit: HKUnit.count().unitDivided(by: .minute())
        )
        async let o2 = optionalLatestSpO2()
        async let vo2 = optionalVO2()
        async let bmi = optionalLatest(
            .bodyMassIndex,
            unit: .count(),
            fromAllTime: true
        )
        async         let lean = optionalLatest(
            .leanBodyMass,
            unit: HKUnit.gramUnit(with: .kilo),
            fromAllTime: true
        )
        async let bodyFat = optionalLatest(
            .bodyFatPercentage,
            unit: .percent(),
            fromAllTime: true
        )
        async let sleep24h = sleepHours(
            from: calendar.date(byAdding: .day, value: -1, to: now) ?? now.addingTimeInterval(-86_400),
            to: now
        )
        async let heightM = optionalLatest(
            .height,
            unit: .meter(),
            fromAllTime: true
        )
        async let weightKg = optionalLatest(
            .bodyMass,
            unit: HKUnit.gramUnit(with: .kilo),
            fromAllTime: true
        )
        async let bps = optionalLatest(
            .bloodPressureSystolic,
            unit: .millimeterOfMercury(),
            fromAllTime: true
        )
        async let bpd = optionalLatest(
            .bloodPressureDiastolic,
            unit: .millimeterOfMercury(),
            fromAllTime: true
        )
        async let hrAvgToday = heartRateAverage(from: startOfToday, to: now)
        async let weekSleep = weekSleepPoints(ending: now, calendar: calendar)
        async let hrLine = heartRateLineNormalized()
        async let hrLatest = optionalLatest(
            .heartRate,
            unit: HKUnit.count().unitDivided(by: .minute())
        )
        async let workouts = countWorkouts(days: 7, ending: now)
        async let mindfulMin = sumMindfulSessionMinutes(days: 7, ending: now)
        async let userProfile = loadUserProfile(
            heightMeters: { await heightM },
            weightKg: { await weightKg }
        )

        let rResting = await resting
        let rHrv = await hrv
        let rResp = await respiratory
        let rSteps = await steps
        let rActive = await activeCal
        let rEx = await exerciseMin
        let rStand = await standHours
        let rDist = await distanceM
        let rFlights = await flights
        let rWalk = await walkHR
        let rO2 = await o2
        let rVo2 = await vo2
        let rBmi = await bmi
        let rLean = await lean
        let rFat = await bodyFat
        let rSleep = await sleep24h
        let rHeight = await heightM
        let rWeight = await weightKg
        let rBps = await bps
        let rBpd = await bpd
        let rHrAvg = await hrAvgToday
        let wSleep = await weekSleep
        let rHrLine = await hrLine
        let rHrLatest = await hrLatest
        let rWorkouts = await workouts
        let rMindful = await mindfulMin
        let prof = await userProfile

        var metrics: [HealthMetric] = [
            metric("Resting Heart Rate", rResting, "bpm", "Most recent resting heart rate sample in HealthKit."),
            metric("Heart Rate Variability", rHrv, "ms", "Latest HRV (SDNN)."),
            metric("Heart Rate (latest)", rHrLatest, "bpm", "Most recent heart rate sample."),
            metric("Heart Rate (today avg)", rHrAvg, "bpm", "Average of heart rate samples from today."),
            metric("Walking HR average", rWalk, "bpm", "Walking heart rate when available from Apple Health."),
            metric("Respiratory Rate", rResp, "br/min", "Latest respiratory rate sample."),
            metric("Oxygen Saturation", rO2, "%", "Latest SpO₂ reading when a pulse oximeter or watch provided it."),
            metric("VO2 Max", rVo2, "mL/kg·min", "Cardio fitness estimate from Apple Health when recorded."),
            metric("Step Count", rSteps, "steps", "Steps recorded today (start of day to now)."),
            metric("Active Energy", rActive, "kcal", "Active calories burned today."),
            metric("Exercise Minutes", rEx, "min", "Apple exercise minutes for today (Move ring)."),
            metric("Stand Hours", rStand, "hrs", "Apple Stand hours closed today (ring progress)."),
            metric("Walking & Running Dist.", (rDist.map { $0 / 1609.34 }), "mi", "Distance walking/running for today in miles."),
            metric("Flights Climbed", rFlights, "flights", "Flights of stairs for today when recorded."),
            metric("Sleep (last 24h asleep)", rSleep, "hrs", "Total asleep time in the last 24 hours from sleep stages."),
            metric("BMI", rBmi, "index", "Body mass index from Health if recorded."),
            metric("Lean Body Mass", rLean, "kg", "Lean body mass if logged."),
            metric("Body Fat", rFat, "%", "Body fat percentage if logged."),
            metric("Height", (rHeight.map { $0 * 100 }), "cm", "Height from Health; centimeters for export."),
            metric("Body Mass", rWeight, "kg", "Weight in kilograms from Health."),
            metric("Blood Pressure (sys)", rBps, "mmHg", "Latest systolic if logged."),
            metric("Blood Pressure (dia)", rBpd, "mmHg", "Latest diastolic if logged."),
            metric("Workouts (7d count)", Double(rWorkouts), "workouts", "Number of workouts in the last 7 days."),
            metric("Mindful (7d)", rMindful, "min", "Mindful minutes inferred from recent mindful session samples.")
        ]

        // Drop metrics that are completely empty only if we have at least one real value elsewhere
        let withValues = metrics.filter { $0.value != nil }
        if withValues.isEmpty, metrics.allSatisfy({ $0.value == nil }) {
            return FetchOutcome(
                snapshot: HealthSnapshot(
                    source: "healthkit",
                    generatedAt: now,
                    metrics: metrics,
                    weekSleep: wSleep,
                    heartRateLineNormalizedYs: rHrLine.isEmpty ? [0.5, 0.5, 0.5] : rHrLine,
                    userProfile: prof
                ),
                userMessage: "No HealthKit data found yet. Open the Health app, add data, or grant read access, then pull to refresh in a build with Health permissions."
            )
        }

        let line = rHrLine.isEmpty
            ? (0..<5).map { _ in CGFloat.random(in: 0.3...0.7) }
            : rHrLine

        return FetchOutcome(
            snapshot: HealthSnapshot(
                source: "healthkit",
                generatedAt: now,
                metrics: metrics,
                weekSleep: wSleep,
                heartRateLineNormalizedYs: line,
                userProfile: prof
            ),
            userMessage: "Loaded \(max(withValues.count, 0)) HealthKit fields with values."
        )
    }

    func metric(_ title: String, _ v: Double?, _ unit: String, _ summary: String) -> HealthMetric {
        HealthMetric(title: title, value: v, unit: unit, summary: summary)
    }

    // MARK: Characteristics + profile

    func loadUserProfile(heightMeters: () async -> Double?, weightKg: () async -> Double?) async -> UserHealthProfile {
        var ageLine = "Not set in Health"
        if let dob = try? healthStore.dateOfBirthComponents().date {
            let years = Calendar.current.dateComponents([.year], from: dob, to: Date()).year ?? 0
            if years > 0 { ageLine = "Age ~\(years) (from DOB in Health)" }
        }

        var sexLine = "Not set"
        if
            let sex = try? healthStore.biologicalSex()
        {
            switch sex.biologicalSex {
            case .female: sexLine = "Female"
            case .male: sexLine = "Male"
            case .other: sexLine = "Other"
            case .notSet: break
            @unknown default: sexLine = "Set in Health"
            }
        }

        let hM = await heightMeters()
        let wK = await weightKg()

        let hStr: String
        if let m = hM, m > 0 {
            let totalIn = m * 39.3701
            let feet = Int(totalIn) / 12
            let inches = Int(totalIn) % 12
            hStr = "\(feet)′ \(inches)″"
        } else {
            hStr = "—"
        }

        let wStr: String
        if let kg = wK, kg > 0 {
            let lb = kg * 2.20462
            wStr = String(format: "%.0f lb (%.0f kg)", lb, kg)
        } else {
            wStr = "—"
        }

        return UserHealthProfile(
            ageDescription: ageLine,
            sexDescription: sexLine,
            heightDescription: hStr,
            weightDescription: wStr,
            isPlaceholder: false
        )
    }

    // MARK: Queries

    func optionalLatest(
        _ id: HKQuantityTypeIdentifier,
        unit: HKUnit,
        fromAllTime: Bool = false
    ) async -> Double? {
        await withCheckedContinuation { cont in
            guard let t = HKObjectType.quantityType(forIdentifier: id) else {
                cont.resume(returning: nil)
                return
            }
            let sort = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            let predicate: NSPredicate? = fromAllTime ? nil : nil
            let query = HKSampleQuery(
                sampleType: t,
                predicate: predicate,
                limit: 1,
                sortDescriptors: sort
            ) { _, samples, _ in
                let q = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                cont.resume(returning: q)
            }
            healthStore.execute(query)
        }
    }

    func optionalCumulative(
        _ id: HKQuantityTypeIdentifier,
        unit: HKUnit,
        from: Date,
        to: Date
    ) async -> Double? {
        await withCheckedContinuation { cont in
            guard let t = HKObjectType.quantityType(forIdentifier: id) else {
                cont.resume(returning: nil)
                return
            }
            let pred = HKQuery.predicateForSamples(withStart: from, end: to)
            let q = HKStatisticsQuery(
                quantityType: t,
                quantitySamplePredicate: pred,
                options: .cumulativeSum
            ) { _, stats, _ in
                cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit))
            }
            healthStore.execute(q)
        }
    }

    /// SpO₂ in Health is stored as 0-1; display as 0-100.
    func optionalLatestSpO2() async -> Double? {
        guard let raw = await optionalLatest(
            .oxygenSaturation,
            unit: .percent()
        ) else { return nil }
        if raw > 0, raw <= 1 { return (raw * 100).rounded() / 1 }
        return raw
    }

    /// VO2 max in mL/(kg·min), using HealthKit’s canonical unit for this identifier.
    func optionalVO2() async -> Double? {
        await withCheckedContinuation { cont in
            guard let t = HKObjectType.quantityType(forIdentifier: .vo2Max) else {
                cont.resume(returning: nil)
                return
            }
            let u = HKUnit.literUnit(with: .milli)
                .unitDivided(by: HKUnit.gramUnit(with: .kilo))
                .unitDivided(by: .minute())
            let sort = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            let q = HKSampleQuery(
                sampleType: t,
                predicate: nil,
                limit: 1,
                sortDescriptors: sort
            ) { _, samples, _ in
                let v = (samples?.first as? HKQuantitySample)?
                    .quantity
                    .doubleValue(for: u)
                cont.resume(returning: v)
            }
            healthStore.execute(q)
        }
    }

    func heartRateAverage(from: Date, to: Date) async -> Double? {
        await withCheckedContinuation { cont in
            guard let t = HKObjectType.quantityType(forIdentifier: .heartRate) else {
                cont.resume(returning: nil)
                return
            }
            let pred = HKQuery.predicateForSamples(withStart: from, end: to)
            let q = HKStatisticsQuery(
                quantityType: t,
                quantitySamplePredicate: pred,
                options: .discreteAverage
            ) { _, stats, _ in
                let v = stats?.averageQuantity()?.doubleValue(
                    for: HKUnit.count().unitDivided(by: .minute())
                )
                cont.resume(returning: v)
            }
            healthStore.execute(q)
        }
    }

    func heartRateLineNormalized() async -> [CGFloat] {
        let end = Date()
        let start = end.addingTimeInterval(-12 * 3600)
        let samples: [HKQuantitySample] = await withCheckedContinuation { cont in
            guard let t = HKObjectType.quantityType(forIdentifier: .heartRate) else {
                cont.resume(returning: [])
                return
            }
            let pred = HKQuery.predicateForSamples(withStart: start, end: end)
            let s = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            let q = HKSampleQuery(
                sampleType: t,
                predicate: pred,
                limit: 80,
                sortDescriptors: s
            ) { _, results, _ in
                cont.resume(returning: (results as? [HKQuantitySample]) ?? [])
            }
            healthStore.execute(q)
        }
        guard !samples.isEmpty else { return [] }
        let bpm = samples.map { $0.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) }
        let minB = bpm.min() ?? 0
        let maxB = bpm.max() ?? 1
        let range = max(maxB - minB, 1)
        return bpm.map { CGFloat(($0 - minB) / range) }
    }

    func weekSleepPoints(ending: Date, calendar: Calendar) async -> [DaySleepPoint] {
        var out: [DaySleepPoint] = []
        for offset in (0..<7).reversed() {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: ending)) else { continue }
            let start = day
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? day
            let hours = await sleepHours(from: start, to: end)
            let sym = calendar.shortWeekdaySymbols[calendar.component(.weekday, from: start) - 1]
            out.append(DaySleepPoint(weekdayLabel: String(sym.prefix(3)), hours: hours))
        }
        return out
    }

    func sleepHours(from: Date, to: Date) async -> Double? {
        await withCheckedContinuation { cont in
            guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
                cont.resume(returning: nil)
                return
            }
            let pred = HKQuery.predicateForSamples(withStart: from, end: to)
            let q = HKSampleQuery(
                sampleType: sleepType,
                predicate: pred,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, _ in
                var total: TimeInterval = 0
                for s in (samples as? [HKCategorySample]) ?? [] where HealthDashboardViewModel.isAsleep(s) {
                    let span = s.endDate.timeIntervalSince(s.startDate)
                    if span > 0 { total += span }
                }
                let h = total / 3600
                cont.resume(returning: h > 0 ? h : nil)
            }
            healthStore.execute(q)
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

    func countWorkouts(days: Int, ending: Date) async -> Int {
        await withCheckedContinuation { cont in
            let start = Calendar.current.date(
                byAdding: .day,
                value: -days,
                to: ending
            ) ?? ending
            let pred = HKQuery.predicateForSamples(withStart: start, end: ending)
            let w = HKObjectType.workoutType()
            let q = HKSampleQuery(
                sampleType: w,
                predicate: pred,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, results, _ in
                cont.resume(returning: (results?.count) ?? 0)
            }
            healthStore.execute(q)
        }
    }

    func sumMindfulSessionMinutes(days: Int, ending: Date) async -> Double? {
        await withCheckedContinuation { cont in
            guard let t = HKObjectType.categoryType(forIdentifier: .mindfulSession) else {
                cont.resume(returning: nil)
                return
            }
            let start = Calendar.current.date(
                byAdding: .day,
                value: -days,
                to: ending
            ) ?? ending
            let pred = HKQuery.predicateForSamples(withStart: start, end: ending)
            let q = HKSampleQuery(
                sampleType: t,
                predicate: pred,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                var total: TimeInterval = 0
                for s in (samples as? [HKCategorySample]) ?? [] {
                    total += s.endDate.timeIntervalSince(s.startDate)
                }
                let m = total / 60
                cont.resume(returning: m > 0 ? m : nil)
            }
            healthStore.execute(q)
        }
    }
}

// MARK: - Simulation

private extension HealthDashboardViewModel {
    static func makeSimulatedFullSnapshot() -> HealthSnapshot {
        let rhr = Double.random(in: 54...64)
        let hrv = Double.random(in: 28...58)
        let steps = Double(Int.random(in: 3200...14_200))
        let active = Double.random(in: 200...800)
        let ex = Double.random(in: 0...60)
        let stand = Double.random(in: 0...8)
        let now = Date()
        let wSleep: [DaySleepPoint] = (0..<7).map { i in
            let label = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][(i + 1) % 7]
            return DaySleepPoint(weekdayLabel: label, hours: Double.random(in: 5.2...8.1))
        }
        let line = (0..<6).map { _ in CGFloat.random(in: 0.25...0.8) }
        return HealthSnapshot(
            source: "simulation",
            generatedAt: now,
            metrics: [
                HealthMetric(title: "Resting Heart Rate", value: rhr, unit: "bpm", summary: "Demo resting HR."),
                HealthMetric(title: "Heart Rate Variability", value: hrv, unit: "ms", summary: "Demo HRV (SDNN)."),
                HealthMetric(title: "Heart Rate (latest)", value: rhr + Double.random(in: 2...20), unit: "bpm", summary: "Demo last HR sample."),
                HealthMetric(title: "Heart Rate (today avg)", value: rhr + 6, unit: "bpm", summary: "Demo daily average HR."),
                HealthMetric(title: "Walking HR average", value: rhr + 8, unit: "bpm", summary: "Demo walking HR average."),
                HealthMetric(title: "Respiratory Rate", value: Double.random(in: 12.5...17.0), unit: "br/min", summary: "Demo respiratory rate."),
                HealthMetric(title: "Oxygen Saturation", value: Double.random(in: 95...100), unit: "%", summary: "Demo SpO₂."),
                HealthMetric(title: "VO2 Max", value: Double.random(in: 35...52), unit: "mL/kg·min", summary: "Demo VO₂ max."),
                HealthMetric(title: "Step Count", value: steps, unit: "steps", summary: "Demo step count for today."),
                HealthMetric(title: "Active Energy", value: active, unit: "kcal", summary: "Demo active calories today."),
                HealthMetric(title: "Exercise Minutes", value: ex, unit: "min", summary: "Demo exercise time."),
                HealthMetric(title: "Stand Hours", value: stand, unit: "hrs", summary: "Demo stand hours."),
                HealthMetric(title: "Walking & Running Dist.", value: steps / 2000, unit: "mi", summary: "Demo distance in miles."),

                HealthMetric(title: "Flights Climbed", value: Double(Int.random(in: 0...18)), unit: "flights", summary: "Demo flights."),
                HealthMetric(title: "Sleep (last 24h asleep)", value: Double.random(in: 5.5...8.0), unit: "hrs", summary: "Demo sleep duration."),
                HealthMetric(title: "BMI", value: Double.random(in: 21...28), unit: "index", summary: "Demo BMI."),
                HealthMetric(title: "Lean Body Mass", value: Double.random(in: 55...70), unit: "kg", summary: "Demo lean mass."),
                HealthMetric(title: "Body Fat", value: Double.random(in: 10...25), unit: "%", summary: "Demo body fat."),

                HealthMetric(title: "Height", value: 180, unit: "cm", summary: "Demo height."),
                HealthMetric(title: "Body Mass", value: Double.random(in: 68...92), unit: "kg", summary: "Demo weight."),

                HealthMetric(title: "Blood Pressure (sys)", value: Double.random(in: 110...128), unit: "mmHg", summary: "Demo BP systolic."),
                HealthMetric(title: "Blood Pressure (dia)", value: Double.random(in: 70...85), unit: "mmHg", summary: "Demo BP diastolic."),

                HealthMetric(title: "Workouts (7d count)", value: Double(Int.random(in: 0...6)), unit: "workouts", summary: "Demo workout count (7d)."),
                HealthMetric(title: "Mindful (7d)", value: Double.random(in: 0...80), unit: "min", summary: "Demo mindful time.")
            ],
            weekSleep: wSleep,
            heartRateLineNormalizedYs: line,
            userProfile: .demo
        )
    }
}

