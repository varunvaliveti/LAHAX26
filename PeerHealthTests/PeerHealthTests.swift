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
                HealthMetric(title: "Sleep Duration", value: 7.2, unit: "hrs", summary: "Overnight")
            ]
        )

        #expect(snapshot.payloadPreview.contains("\"source\": \"simulation\""))
        #expect(snapshot.payloadPreview.contains("\"name\": \"Resting Heart Rate\""))
        #expect(snapshot.payloadPreview.contains("\"value\": 7.20"))
    }

    @Test func integerMetricsFormatWithoutDecimalPlaces() async throws {
        let metric = HealthMetric(title: "Step Count", value: 8000, unit: "steps", summary: "Daily activity")

        #expect(metric.formattedValue == "8000 steps")
    }
}
