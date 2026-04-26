//
//  PHComponents.swift
//  PeerHealth
//

import SwiftUI

// MARK: - Tabs

enum PHTab: String, CaseIterable, Identifiable {
    case home, insights, chat, profile
    var id: String { rawValue }

    var label: String {
        switch self {
        case .home: return "Home"
        case .insights: return "Insights"
        case .chat: return "Chat"
        case .profile: return "You"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .insights: return "chart.line.uptrend.xyaxis"
        case .chat: return "ellipsis.bubble.fill"
        case .profile: return "person.fill"
        }
    }
}

struct PHTabBar: View {
    @Binding var selected: PHTab
    var dark: Bool = false

    var body: some View {
        ZStack {
            backdrop
            HStack(spacing: 0) {
                ForEach(PHTab.allCases) { tab in
                    Button {
                        selected = tab
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: tab.symbol)
                                .font(.system(size: 18, weight: .semibold))
                            Text(tab.label)
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(color(for: tab))
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(dark ? 0.4 : 0.08), radius: dark ? 24 : 24, x: 0, y: dark ? 8 : 6)
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
    }

    private var backdrop: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(dark ? Color(white: 0.11).opacity(0.62) : Color.white.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(
                        dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06),
                        lineWidth: 0.5
                    )
            )
    }

    private func color(for tab: PHTab) -> Color {
        let isActive = tab == selected
        if dark {
            return isActive ? .white : Color.white.opacity(0.45)
        }
        return isActive ? Color(red: 0.07, green: 0.07, blue: 0.09) : Color(red: 0.24, green: 0.24, blue: 0.26).opacity(0.55)
    }
}

// MARK: - Glass card

struct GlassCard<Content: View>: View {
    var dark: Bool = false
    var padding: CGFloat = 18
    var radius: CGFloat = 22
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(dark ? Color(white: 0.12).opacity(0.55) : Color.white.opacity(0.62))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(
                            dark ? Color.white.opacity(0.08) : Color.white.opacity(0.7),
                            lineWidth: 0.5
                        )
                )
                .shadow(
                    color: dark ? Color.black.opacity(0.3) : Color(red: 0.08, green: 0.08, blue: 0.16).opacity(0.06),
                    radius: dark ? 20 : 22,
                    x: 0,
                    y: dark ? 4 : 6
                )

            content
                .padding(padding)
        }
    }
}

// MARK: - Tiny chip (action chips on Home V4)

struct PHChip: View {
    let label: String
    var action: (() -> Void)?

    var body: some View {
        Button {
            action?()
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.09))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.7))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Heart-rate sparkline

struct HRSparkline: View {
    var color: Color = Color(red: 1.0, green: 0.23, blue: 0.36)
    var stroke: CGFloat = 2
    var height: CGFloat = 50

    private static let points: [Double] = {
        let n = 60
        return (0..<n).map { i in
            let t = Double(i) / Double(n)
            return 60 + sin(t * 9) * 8 + sin(t * 4 + 1) * 5 + cos(t * 16) * 3
        }
    }()

    var body: some View {
        GeometryReader { geo in
            let pts = Self.points
            let minV = pts.min() ?? 0
            let maxV = pts.max() ?? 1
            let w = geo.size.width
            let h = geo.size.height

            let line = Path { path in
                for (i, v) in pts.enumerated() {
                    let x = CGFloat(i) / CGFloat(pts.count - 1) * w
                    let yNorm = (v - minV) / max(0.001, maxV - minV)
                    let y = h - yNorm * h * 0.85 - h * 0.075
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }

            let fill = Path { path in
                path.addPath(line)
                path.addLine(to: CGPoint(x: w, y: h))
                path.addLine(to: CGPoint(x: 0, y: h))
                path.closeSubpath()
            }

            ZStack {
                fill
                    .fill(LinearGradient(
                        colors: [color.opacity(0.25), color.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                line
                    .stroke(color, style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(height: height)
    }
}

// MARK: - Weekly sleep bars

struct SleepBars: View {
    let data: [(label: String, hours: Double?)]
    var accent: Color = Color(red: 0.37, green: 0.36, blue: 0.90)
    var height: CGFloat = 70

    var body: some View {
        GeometryReader { geo in
            let count = max(1, data.count)
            let gap: CGFloat = 8
            let barW = (geo.size.width - CGFloat(count - 1) * gap) / CGFloat(count)
            let chartH = height - 22
            let maxH: Double = 9.0

            HStack(alignment: .bottom, spacing: gap) {
                ForEach(Array(data.enumerated()), id: \.offset) { _, d in
                    VStack(spacing: 6) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: barW / 2.5, style: .continuous)
                                .fill(Color.black.opacity(0.04))
                                .frame(height: chartH)
                            if let h = d.hours, h > 0 {
                                RoundedRectangle(cornerRadius: barW / 2.5, style: .continuous)
                                    .fill(accent.opacity(0.85))
                                    .frame(height: CGFloat(min(h, maxH) / maxH) * chartH)
                            }
                        }
                        .frame(width: barW)
                        Text(d.label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.45))
                    }
                }
            }
        }
        .frame(height: height)
    }
}

// MARK: - Section label (uppercase tracked)

struct SectionLabel: View {
    let text: String
    var dark: Bool = false

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(dark ? Color.white.opacity(0.5) : Color.black.opacity(0.45))
            .padding(.horizontal, 6)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
