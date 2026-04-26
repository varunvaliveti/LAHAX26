//
//  PeerHealthTests.swift
//  PeerHealthTests
//
//  Created by Varun Valiveti on 4/25/26.
//

import Foundation
import Testing
@testable import PeerHealth

struct PeerHealthTests {

    @Test func payloadPreviewIncludesMetricNames() async throws {
        let snapshot = HealthSnapshot(
            source: "simulation",
            generatedAt: Date(timeIntervalSince1970: 0),
            metrics: [
                HealthMetric(title: "Resting Heart Rate", value: 60, unit: "bpm", summary: "Baseline"),
                HealthMetric(title: "Sleep (last 24h asleep)", value: 7.2, unit: "hrs", summary: "Overnight")
            ],
            weekSleep: [],
            heartRateLineNormalizedYs: [0.5, 0.5],
            userProfile: UserHealthProfile(
                ageDescription: "30",
                sexDescription: "Not set",
                heightDescription: "—",
                weightDescription: "—",
                isPlaceholder: true
            )
        )

        #expect(snapshot.payloadPreview.contains("\"source\": \"simulation\""))
        #expect(snapshot.payloadPreview.contains("\"name\": \"Resting Heart Rate\""))
        #expect(snapshot.payloadPreview.contains("\"value\": 7.20"))
    }

    @Test func integerMetricsFormatWithoutDecimalPlaces() async throws {
        let metric = HealthMetric(title: "Step Count", value: 8000, unit: "steps", summary: "Daily activity")

        #expect(metric.formattedValue == "8000 steps")
    }

    @Test func healthMetricWithNilValueFormatsAsEmDash() {
        let metric = HealthMetric(
            title: "Resting Heart Rate",
            value: nil,
            unit: "bpm",
            summary: "No data"
        )
        #expect(metric.formattedValue == "—")
    }

    @Test func averageSleepThisWeekSkipsNilHours() {
        let snapshot = HealthSnapshot(
            source: "healthkit",
            generatedAt: .now,
            metrics: [],
            weekSleep: [
                DaySleepPoint(weekdayLabel: "Mon", hours: 6.0),
                DaySleepPoint(weekdayLabel: "Tue", hours: nil),
                DaySleepPoint(weekdayLabel: "Wed", hours: 8.0)
            ],
            heartRateLineNormalizedYs: [],
            userProfile: UserHealthProfile(
                ageDescription: "—",
                sexDescription: "—",
                heightDescription: "—",
                weightDescription: "—",
                isPlaceholder: true
            )
        )
        #expect(snapshot.averageSleepThisWeek == 7.0)
    }

    @Test func payloadPreviewSerializesNullForMissingValues() {
        let snapshot = HealthSnapshot(
            source: "healthkit",
            generatedAt: Date(timeIntervalSince1970: 0),
            metrics: [
                HealthMetric(title: "Step Count", value: nil, unit: "steps", summary: "None")
            ],
            weekSleep: [],
            heartRateLineNormalizedYs: [0.5],
            userProfile: UserHealthProfile(
                ageDescription: "—",
                sexDescription: "—",
                heightDescription: "—",
                weightDescription: "—",
                isPlaceholder: true
            )
        )
        #expect(snapshot.payloadPreview.contains("\"value\": null"))
    }
}
