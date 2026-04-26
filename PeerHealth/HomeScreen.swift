//
//  HomeScreen.swift
//  PeerHealth
//

import SwiftUI

struct HomeScreen: View {
    @ObservedObject var viewModel: HealthDashboardViewModel
    @ObservedObject var connectionManager: TCPConnectionManager
    var useDemoData: Bool

    @AppStorage("peerHealthCompanionName") private var companionName = "GX10"
    @AppStorage("peerHealthUserName") private var userName = ""

    var body: some View {
        PointerTrackingScreen { pointer in
            screenBody(pointer: pointer)
        }
    }

    @ViewBuilder
    private func screenBody(pointer: UnitPoint?) -> some View {
        ZStack {
            Color(red: 0.98, green: 0.98, blue: 0.97).ignoresSafeArea()
            JellyBackground(palette: .iridescent, blur: 85, intensity: 1.0, speed: 0.7, opacity: 0.45, pointer: pointer)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    terminalHeader
                        .padding(.horizontal, 18)
                        .padding(.top, 6)
                        .padding(.bottom, 10)

                    Rectangle()
                        .fill(Color.black.opacity(0.12))
                        .frame(height: 1)
                        .padding(.bottom, 10)

                    heroBlock
                        .padding(.horizontal, 18)
                        .padding(.top, 4)

                    progressBar
                        .padding(.horizontal, 18)
                        .padding(.top, 4)
                        .padding(.bottom, 14)

                    metricsGrid
                        .padding(.horizontal, 16)

                    agentQuoteBox
                        .padding(.horizontal, 16)
                        .padding(.top, 14)

                    terminalLog
                        .padding(.horizontal, 18)
                        .padding(.top, 12)

                    statusFooter
                        .padding(.horizontal, 14)
                        .padding(.top, 16)
                }
                .padding(.bottom, 130)
            }
        }
        .refreshable {
            await viewModel.bootstrap(useSimulation: useDemoData)
        }
    }

    // MARK: - Terminal header

    private var terminalHeader: some View {
        HStack {
            HStack(spacing: 6) {
                Text("peerhealth@\(companionShortName):~$")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(0.2)
                    .foregroundStyle(Color.black)
                Circle()
                    .fill(connectionManager.isConnected
                          ? Color(red: 0.20, green: 0.78, blue: 0.35)
                          : Color(red: 0.95, green: 0.66, blue: 0.07))
                    .frame(width: 7, height: 7)
            }
            Spacer()
            Text(headerDateLine.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(Color.black.opacity(0.55))
        }
    }

    private var companionShortName: String {
        let raw = companionName.trimmingCharacters(in: .whitespaces)
        if raw.isEmpty { return "gx10" }
        return raw.lowercased().replacingOccurrences(of: " ", with: "-")
    }

    private var headerDateLine: String {
        let f = DateFormatter()
        f.dateFormat = "EEE · HH:mm · MM/dd"
        return f.string(from: .now)
    }

    // MARK: - Hero block

    private var heroBlock: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text("[ READINESS ]")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(Color.black)
                Text("\(readinessScore)")
                    .font(.system(size: 124, weight: .bold, design: .monospaced))
                    .tracking(-5)
                    .foregroundStyle(Color.black)
                    .padding(.top, 4)
                    .frame(alignment: .leading)
            }

            VStack(alignment: .trailing, spacing: 0) {
                Text("HR · LIVE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(Color.black.opacity(0.55))
                Text(asciiHR)
                    .font(.system(size: 14, design: .monospaced))
                    .tracking(-0.5)
                    .foregroundStyle(Color.black)
                    .lineLimit(1)
                    .padding(.top, 6)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(hrLatestText)
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .tracking(-0.8)
                        .foregroundStyle(Color.black)
                    Text("bpm")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.black.opacity(0.5))
                }
                .padding(.top, 4)
            }
            .padding(.bottom, 8)
        }
    }

    private static let asciiChars: [Character] = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
    private var asciiHR: String {
        let n = 28
        var s = ""
        for i in 0..<n {
            let t = Double(i) / Double(n)
            let v = 0.5 + 0.35 * sin(t * 9) + 0.18 * sin(t * 4 + 1) + 0.12 * cos(t * 16)
            let idx = max(0, min(Self.asciiChars.count - 1, Int((v * Double(Self.asciiChars.count - 1)).rounded(.down))))
            s.append(Self.asciiChars[idx])
        }
        return s
    }

    // MARK: - Progress bar

    private var progressBar: some View {
        let total = 40
        let filled = max(0, min(total, Int((Double(readinessScore) / 100.0 * Double(total)).rounded())))
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            HStack(spacing: 0) {
                Text(String(repeating: "█", count: filled))
                    .foregroundStyle(Color.black)
                Text(String(repeating: "░", count: total - filled))
                    .foregroundStyle(Color.black.opacity(0.18))
            }
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(0.3)
            .lineLimit(1)
            .minimumScaleFactor(0.6)

            Text("\(readinessScore)/100")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.black)

            Text(deltaText)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(red: 0.20, green: 0.78, blue: 0.35))
        }
    }

    private var deltaText: String {
        let delta = readinessScore - 78
        if delta >= 0 { return "↑ +\(delta)" }
        return "↓ \(delta)"
    }

    // MARK: - Bordered metric grid

    private var metricsGrid: some View {
        let cells: [MonoCellData] = [
            .init(key: "RHR",   value: rhrText.value,   unit: rhrText.unit,   delta: rhrText.delta,   ok: true),
            .init(key: "HRV",   value: hrvText.value,   unit: hrvText.unit,   delta: hrvText.delta,   ok: true),
            .init(key: "RESP",  value: respText.value,  unit: respText.unit,  delta: "±0",            ok: false),
            .init(key: "SLEEP", value: sleepText.value, unit: sleepText.unit, delta: sleepText.delta, ok: true),
            .init(key: "STEPS", value: stepsText.value, unit: "",             delta: stepsText.delta, ok: false),
            .init(key: "KCAL",  value: kcalText.value,  unit: "",             delta: kcalText.delta,  ok: true)
        ]
        return GeometryReader { geo in
            let colW = geo.size.width / 3
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    MonoCellView(data: cells[0], colWidth: colW, hasRightBorder: true,  hasTopBorder: false)
                    MonoCellView(data: cells[1], colWidth: colW, hasRightBorder: true,  hasTopBorder: false)
                    MonoCellView(data: cells[2], colWidth: colW, hasRightBorder: false, hasTopBorder: false)
                }
                HStack(spacing: 0) {
                    MonoCellView(data: cells[3], colWidth: colW, hasRightBorder: true,  hasTopBorder: true)
                    MonoCellView(data: cells[4], colWidth: colW, hasRightBorder: true,  hasTopBorder: true)
                    MonoCellView(data: cells[5], colWidth: colW, hasRightBorder: false, hasTopBorder: true)
                }
            }
        }
        .frame(height: 138)
        .overlay(
            Rectangle().stroke(Color.black.opacity(0.16), lineWidth: 1)
        )
    }

    // MARK: - Agent quote box

    private var agentQuoteBox: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(">")
                Text("AGENT · \(timeShort)")
            }
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(1.4)
            .foregroundStyle(Color.black.opacity(0.55))

            VStack(alignment: .leading, spacing: 4) {
                Text("hrv recovered fully. zone-2 walk logged.")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.black)
                HStack(spacing: 0) {
                    Text("sleep window opens in ")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.black)
                    Text("56m")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.black)
                    Text(".")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.black)
                }
            }
            .padding(.top, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Rectangle().fill(.ultraThinMaterial)
                .overlay(Rectangle().fill(Color.white.opacity(0.55)))
        )
        .overlay(Rectangle().stroke(Color.black.opacity(0.16), lineWidth: 1))
    }

    // MARK: - Terminal log

    private var terminalLog: some View {
        let lines = logLines
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("›")
                        .foregroundStyle(line.color)
                    Text(line.text)
                        .foregroundStyle(Color.black.opacity(0.7))
                }
                .font(.system(size: 10.5, design: .monospaced))
                .lineSpacing(6)
            }
        }
    }

    private var logLines: [(text: String, color: Color)] {
        let now = timeShort
        let mins = Calendar.current.component(.minute, from: .now)
        let prev1 = String(format: "%02d:%02d", Calendar.current.component(.hour, from: .now), max(0, mins - 3))
        let prev2 = String(format: "%02d:%02d", Calendar.current.component(.hour, from: .now), max(0, mins - 5))
        let prev3 = String(format: "%02d:%02d", Calendar.current.component(.hour, from: .now), max(0, mins - 32))

        let companion = companionShortName
        return [
            ("\(now) · synced \(syncedSamples) samples", Color(red: 0.20, green: 0.78, blue: 0.35)),
            ("\(now) · agent: \(agentLogLine)",         Color(red: 0.20, green: 0.78, blue: 0.35)),
            ("\(prev1) · sleep window in 56m",          Color(red: 0.37, green: 0.36, blue: 0.90)),
            ("\(prev2) · workout: 32m walk · z2",       Color.black.opacity(0.5)),
            ("\(prev3) · anchor saved · hr@\(companion)", Color.black.opacity(0.5))
        ]
    }

    private var syncedSamples: Int {
        let count = viewModel.snapshot.metrics.filter { $0.value != nil }.count
        return max(count * 12, connectionManager.isConnected ? 142 : 0)
    }

    private var agentLogLine: String {
        if readinessScore >= 78 { return "hrv trending up" }
        if readinessScore >= 60 { return "signals look mixed" }
        return "recovery looks light"
    }

    // MARK: - Status footer

    private var statusFooter: some View {
        HStack {
            HStack(spacing: 4) {
                Circle()
                    .fill(connectionManager.isConnected
                          ? Color(red: 0.20, green: 0.78, blue: 0.35)
                          : Color(red: 0.95, green: 0.66, blue: 0.07))
                    .frame(width: 7, height: 7)
                Text(companionDisplayName.uppercased())
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(Color.black.opacity(0.7))
            }
            Spacer()
            Text(throughputText)
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(Color.black.opacity(0.7))
            Spacer()
            Text(syncStatusText)
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(syncStatusColor)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .overlay(
            Rectangle()
                .fill(Color.black.opacity(0.12))
                .frame(height: 1),
            alignment: .top
        )
    }

    private var companionDisplayName: String {
        let raw = companionName.trimmingCharacters(in: .whitespaces)
        return raw.isEmpty ? "GX10" : raw
    }

    private var throughputText: String {
        if connectionManager.isConnected {
            return "↑\(String(format: "%.1f", upKB))KB ↓\(String(format: "%.1f", downKB))KB"
        }
        return "↑0.0KB ↓0.0KB"
    }

    private var upKB: Double {
        // synthesize from sample count so it feels live
        Double(syncedSamples) * 0.03
    }

    private var downKB: Double {
        connectionManager.isConnected ? 0.8 : 0.0
    }

    private var syncStatusText: String {
        connectionManager.isConnected ? "SYNCED" : "OFFLINE"
    }

    private var syncStatusColor: Color {
        connectionManager.isConnected
            ? Color(red: 0.20, green: 0.78, blue: 0.35)
            : Color(red: 0.95, green: 0.66, blue: 0.07)
    }

    private var timeShort: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: .now)
    }

    // MARK: - Metric helpers

    private struct MetricBits { let value: String; let unit: String; let delta: String }

    private func metric(_ name: String) -> Double? {
        viewModel.snapshot.metrics.first(where: { $0.title == name })?.value
    }

    private var rhrText: MetricBits {
        guard let v = metric("Resting Heart Rate") else { return .init(value: "—", unit: "bpm", delta: "--") }
        let i = Int(v.rounded())
        return .init(value: "\(i)", unit: "bpm", delta: i < 60 ? "−\(60 - i)" : "+\(i - 60)")
    }
    private var hrvText: MetricBits {
        guard let v = metric("Heart Rate Variability") else { return .init(value: "—", unit: "ms", delta: "--") }
        let i = Int(v.rounded())
        let baseline = 50
        return .init(value: "\(i)", unit: "ms", delta: i >= baseline ? "+\(i - baseline)" : "−\(baseline - i)")
    }
    private var respText: MetricBits {
        guard let v = metric("Respiratory Rate") else { return .init(value: "—", unit: "br/m", delta: "±0") }
        return .init(value: "\(Int(v.rounded()))", unit: "br/m", delta: "±0")
    }
    private var sleepText: MetricBits {
        guard let v = metric("Sleep (last 24h asleep)") else { return .init(value: "—", unit: "h", delta: "--") }
        let h = Int(v)
        let m = Int(((v - Double(h)) * 60).rounded())
        return .init(value: "\(h):\(String(format: "%02d", m))", unit: "h", delta: v >= 7 ? "ok" : "low")
    }
    private var stepsText: MetricBits {
        guard let v = metric("Step Count") else { return .init(value: "—", unit: "", delta: "--") }
        let pct = Int((min(v / 10000.0, 1.0) * 100).rounded())
        return .init(value: "\(Int(v.rounded()))", unit: "", delta: "\(pct)%")
    }
    private var kcalText: MetricBits {
        guard let v = metric("Active Energy") else { return .init(value: "—", unit: "", delta: "--") }
        let pct = Int(((v - 400) / 400 * 100).rounded())
        return .init(value: "\(Int(v.rounded()))", unit: "", delta: pct >= 0 ? "+\(pct)%" : "\(pct)%")
    }

    private var hrLatestText: String {
        if let v = metric("Heart Rate (latest)") { return "\(Int(v.rounded()))" }
        if let v = metric("Heart Rate (today avg)") { return "\(Int(v.rounded()))" }
        if let v = metric("Resting Heart Rate") { return "\(Int(v.rounded()))" }
        return "—"
    }

    private var readinessScore: Int {
        let hrv = metric("Heart Rate Variability") ?? 50
        let rhr = metric("Resting Heart Rate") ?? 60
        let sleep = metric("Sleep (last 24h asleep)") ?? 7
        let raw = 70 + (hrv - 40) * 0.5 + (60 - rhr) * 0.6 + (sleep - 7) * 4
        return max(0, min(100, Int(raw.rounded())))
    }
}

// MARK: - Bordered cell

private struct MonoCellData {
    let key: String
    let value: String
    let unit: String
    let delta: String
    let ok: Bool
}

private struct MonoCellView: View {
    let data: MonoCellData
    let colWidth: CGFloat
    let hasRightBorder: Bool
    let hasTopBorder: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(data.key)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(Color.black.opacity(0.55))

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(data.value)
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .tracking(-0.6)
                    .foregroundStyle(Color.black)
                if !data.unit.isEmpty {
                    Text(data.unit)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.black.opacity(0.5))
                }
            }
            .padding(.top, 4)

            Text(data.delta)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(data.ok
                                 ? Color(red: 0.20, green: 0.78, blue: 0.35)
                                 : Color.black.opacity(0.5))
                .padding(.top, 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.top, hasTopBorder ? 11 : 10)
        .padding(.bottom, 8)
        .frame(width: colWidth, height: 69, alignment: .topLeading)
        .overlay(alignment: .trailing) {
            if hasRightBorder {
                Rectangle()
                    .fill(Color.black.opacity(0.16))
                    .frame(width: 1)
            }
        }
        .overlay(alignment: .top) {
            if hasTopBorder {
                Rectangle()
                    .fill(Color.black.opacity(0.16))
                    .frame(height: 1)
            }
        }
    }
}
