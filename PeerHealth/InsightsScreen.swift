//
//  InsightsScreen.swift
//  PeerHealth
//

import SwiftUI

struct InsightsScreen: View {
    @ObservedObject var viewModel: HealthDashboardViewModel
    var useDemoData: Bool

    var body: some View {
        PointerTrackingScreen { pointer in
            screenBody(pointer: pointer)
        }
    }

    @ViewBuilder
    private func screenBody(pointer: UnitPoint?) -> some View {
        ZStack {
            Color(red: 0.97, green: 0.96, blue: 0.95).ignoresSafeArea()
            JellyBackground(palette: .iridescent, blur: 60, intensity: 1.0, speed: 0.7, opacity: 0.9, pointer: pointer)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    header
                        .padding(.horizontal, 22)
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                    heroRHRCard
                        .padding(.horizontal, 16)

                    metricTiles
                        .padding(.horizontal, 16)

                    sleepCard
                        .padding(.horizontal, 16)

                    heartRateTrendCard
                        .padding(.horizontal, 16)

                    bodyStatsCard
                        .padding(.horizontal, 16)

                    allMetricsCard
                        .padding(.horizontal, 16)
                }
                .padding(.bottom, 130)
            }
        }
        .refreshable {
            await viewModel.bootstrap(useSimulation: useDemoData)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(dateLabel.uppercased())
                .font(.system(size: 13, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Color.black.opacity(0.42))
            Text("Insights")
                .font(.system(size: 32, weight: .bold))
                .tracking(-0.8)
                .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.09))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Hero RHR card

    private var heroRHRCard: some View {
        GlassCard(padding: 18, radius: 26) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 6) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color(red: 1.0, green: 0.23, blue: 0.36))
                            Text("RESTING HEART RATE")
                                .font(.system(size: 12, weight: .semibold))
                                .tracking(0.4)
                                .foregroundStyle(Color.black.opacity(0.55))
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(rhrText)
                                .font(.system(size: 56, weight: .bold))
                                .tracking(-2)
                                .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.09))
                            Text("bpm")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.black.opacity(0.5))
                        }
                        .padding(.top, 8)

                        Text(rhrTrend)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(rhrTrendColor)
                            .padding(.top, 6)
                    }
                    Spacer()
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(red: 1.0, green: 0.23, blue: 0.36).opacity(0.1))
                        Image(systemName: "heart.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color(red: 1.0, green: 0.23, blue: 0.36))
                    }
                    .frame(width: 50, height: 50)
                }

                HRSparkline(height: 50)
            }
        }
    }

    // MARK: - 2x2 metric tiles

    private var metricTiles: some View {
        let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return LazyVGrid(columns: cols, spacing: 10) {
            SmallTile(symbol: "flame.fill",
                      color: Color(red: 1.0, green: 0.42, blue: 0.21),
                      label: "Active",
                      value: kcalText,
                      unit: "kcal",
                      trend: kcalTrend)
            SmallTile(symbol: "figure.walk",
                      color: Color(red: 0.20, green: 0.78, blue: 0.35),
                      label: "Steps",
                      value: stepsText,
                      unit: "",
                      trend: stepsTrend)
            SmallTile(symbol: "moon.fill",
                      color: Color(red: 0.37, green: 0.36, blue: 0.90),
                      label: "Sleep",
                      value: sleepText,
                      unit: "",
                      trend: sleepTrend)
            SmallTile(symbol: "lungs.fill",
                      color: Color(red: 0.35, green: 0.78, blue: 0.98),
                      label: "HRV",
                      value: hrvText,
                      unit: "ms",
                      trend: hrvTrend)
        }
    }

    // MARK: - Sleep card

    private var sleepCard: some View {
        GlassCard(padding: 16, radius: 22) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("SLEEP · 7 DAYS")
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(0.4)
                        .foregroundStyle(Color.black.opacity(0.55))
                    Spacer()
                    Text(weekAvgSleepLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.4))
                }
                SleepBars(data: weekSleepData, height: 90)
            }
        }
    }

    // MARK: - Heart rate trend card

    private var heartRateTrendCard: some View {
        GlassCard(padding: 16, radius: 22) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("HEART RATE · TODAY")
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(0.4)
                        .foregroundStyle(Color.black.opacity(0.55))
                    Spacer()
                    Text(hrAvgLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.4))
                }
                if viewModel.snapshot.heartRateLineNormalizedYs.count >= 2 {
                    HeartRateLine(ys: viewModel.snapshot.heartRateLineNormalizedYs)
                        .frame(height: 70)
                } else {
                    Text("Add heart rate samples in Health for an intraday line")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.black.opacity(0.45))
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Body stats card

    private var bodyStatsCard: some View {
        GlassCard(padding: 16, radius: 22) {
            VStack(alignment: .leading, spacing: 14) {
                Text("BODY")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(Color.black.opacity(0.55))

                HStack(spacing: 0) {
                    StatColumn(label: "Age", value: viewModel.snapshot.userProfile.ageDescription)
                    Divider().frame(width: 0.5).overlay(Color.black.opacity(0.08))
                    StatColumn(label: "Height", value: viewModel.snapshot.userProfile.heightDescription)
                    Divider().frame(width: 0.5).overlay(Color.black.opacity(0.08))
                    StatColumn(label: "Weight", value: viewModel.snapshot.userProfile.weightDescription)
                }
            }
        }
    }

    // MARK: - All metrics card

    private var allMetricsCard: some View {
        GlassCard(padding: 16, radius: 22) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("ALL METRICS")
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(0.4)
                        .foregroundStyle(Color.black.opacity(0.55))
                    Spacer()
                    Text("\(viewModel.snapshot.metrics.filter { $0.value != nil }.count) with values")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.black.opacity(0.4))
                }

                VStack(spacing: 0) {
                    ForEach(Array(viewModel.snapshot.metrics.enumerated()), id: \.element.id) { idx, metric in
                        DetailRow(metric: metric, isLast: idx == viewModel.snapshot.metrics.count - 1)
                    }
                }
            }
        }
    }

    // MARK: - Derived values

    private var dateLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE · MMM d"
        return f.string(from: .now)
    }

    private func metricValue(_ name: String) -> Double? {
        viewModel.snapshot.metrics.first(where: { $0.title == name })?.value
    }

    private var rhrText: String {
        guard let v = metricValue("Resting Heart Rate") else { return "—" }
        return "\(Int(v.rounded()))"
    }

    private var rhrTrend: String {
        guard let v = metricValue("Resting Heart Rate") else { return "No baseline yet" }
        let baseline: Double = 60
        if v < baseline { return "↓ \(Int((baseline - v).rounded())) below your 7-day avg" }
        if v > baseline { return "↑ \(Int((v - baseline).rounded())) above your 7-day avg" }
        return "On baseline"
    }

    private var rhrTrendColor: Color {
        guard let v = metricValue("Resting Heart Rate") else { return Color.black.opacity(0.5) }
        return v <= 60 ? Color(red: 0.20, green: 0.78, blue: 0.35) : Color(red: 0.95, green: 0.66, blue: 0.07)
    }

    private var kcalText: String {
        guard let v = metricValue("Active Energy") else { return "—" }
        return "\(Int(v.rounded()))"
    }
    private var kcalTrend: String {
        guard let v = metricValue("Active Energy") else { return "—" }
        let pct = Int(((v - 400) / 400 * 100).rounded())
        return pct >= 0 ? "+\(pct)% vs avg" : "\(pct)% vs avg"
    }

    private var stepsText: String {
        guard let v = metricValue("Step Count") else { return "—" }
        return v.formatted(.number.grouping(.automatic))
    }
    private var stepsTrend: String {
        guard let v = metricValue("Step Count") else { return "—" }
        let pct = Int((min(v / 10000.0, 1.0) * 100).rounded())
        return "\(pct)% goal"
    }

    private var sleepText: String {
        guard let v = metricValue("Sleep (last 24h asleep)") else { return "—" }
        let h = Int(v)
        let m = Int(((v - Double(h)) * 60).rounded())
        return "\(h)h \(String(format: "%02d", m))m"
    }
    private var sleepTrend: String {
        guard let v = metricValue("Sleep (last 24h asleep)") else { return "—" }
        if v >= 8 { return "deep night" }
        if v >= 7 { return "restful" }
        if v >= 6 { return "light" }
        return "short"
    }

    private var hrvText: String {
        guard let v = metricValue("Heart Rate Variability") else { return "—" }
        return "\(Int(v.rounded()))"
    }
    private var hrvTrend: String {
        guard let v = metricValue("Heart Rate Variability") else { return "—" }
        if v >= 60 { return "strong" }
        if v >= 40 { return "steady" }
        return "low"
    }

    private var weekSleepData: [(label: String, hours: Double?)] {
        viewModel.snapshot.weekSleep.map { ($0.weekdayLabel, $0.hours) }
    }

    private var weekAvgSleepLabel: String {
        guard let avg = viewModel.snapshot.averageSleepThisWeek else { return "—" }
        return String(format: "avg %.1fh", avg)
    }

    private var hrAvgLabel: String {
        if let v = metricValue("Heart Rate (today avg)") { return "avg \(Int(v.rounded())) bpm" }
        if let v = metricValue("Resting Heart Rate") { return "rest \(Int(v.rounded())) bpm" }
        return "—"
    }
}

// MARK: - Sub-components

private struct SmallTile: View {
    let symbol: String
    let color: Color
    let label: String
    let value: String
    let unit: String
    let trend: String

    var body: some View {
        GlassCard(padding: 14, radius: 18) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(color)
                    Text(label.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.3)
                        .foregroundStyle(Color.black.opacity(0.55))
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(size: 24, weight: .bold))
                        .tracking(-0.6)
                        .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.09))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if !unit.isEmpty {
                        Text(unit)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.45))
                    }
                }
                .padding(.top, 6)
                Text(trend)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.42))
                    .padding(.top, 2)
            }
        }
    }
}

private struct StatColumn: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Color.black.opacity(0.5))
            Text(value.isEmpty ? "—" : value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.09))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
    }
}

private struct DetailRow: View {
    let metric: HealthMetric
    let isLast: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(metric.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.09))
                Spacer()
                Text(displayValue)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(metric.value == nil ? Color.black.opacity(0.35) : Color.black.opacity(0.7))
            }
            .padding(.vertical, 10)

            if !isLast {
                Rectangle()
                    .fill(Color.black.opacity(0.06))
                    .frame(height: 0.5)
            }
        }
    }

    private var displayValue: String {
        guard let v = metric.value else { return "—" }
        if v.rounded() == v {
            return "\(Int(v)) \(metric.unit)"
        }
        return String(format: "%.1f %@", v, metric.unit)
    }
}

private struct HeartRateLine: View {
    let ys: [CGFloat]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let count = max(2, ys.count)

            let path = Path { p in
                for (i, y) in ys.enumerated() {
                    let x = CGFloat(i) / CGFloat(count - 1) * w
                    let yPx = h - y * h * 0.8 - h * 0.1
                    if i == 0 { p.move(to: CGPoint(x: x, y: yPx)) }
                    else { p.addLine(to: CGPoint(x: x, y: yPx)) }
                }
            }

            path.stroke(
                Color(red: 0.46, green: 0.52, blue: 0.64),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
            )
        }
    }
}
