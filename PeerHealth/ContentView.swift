//
//  ContentView.swift
//  PeerHealth
//
//  Created by Varun Valiveti on 4/25/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = HealthDashboardViewModel()
    @State private var selectedTab: AppTab = .home
    @AppStorage("peerHealthUseDemoData") private var useDemoData = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.white
                .ignoresSafeArea()

            Group {
                switch selectedTab {
                case .home:
                    HomeTabView(
                        viewModel: viewModel,
                        useDemoData: useDemoData,
                        onOpenChat: { selectedTab = .chat }
                    )
                case .chat:
                    ChatTabView()
                case .profile:
                    ProfileTabView(
                        viewModel: viewModel,
                        useDemoData: $useDemoData
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            bottomTabBar
        }
        .task {
            await viewModel.bootstrap(useSimulation: useDemoData)
        }
        .onChange(of: useDemoData) { _, new in
            Task { await viewModel.bootstrap(useSimulation: new) }
        }
    }

    private var bottomTabBar: some View {
        HStack {
            tabItem(symbol: "house.fill", title: "Home", tab: .home)
            Spacer()
            tabItem(symbol: "bubble.left", title: "Chat", tab: .chat)
            Spacer()
            tabItem(symbol: "person", title: "Profile", tab: .profile)
        }
        .padding(.horizontal, 38)
        .padding(.top, 14)
        .padding(.bottom, 24)
        .background(
            Rectangle()
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.04), radius: 8, y: -2)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func tabItem(symbol: String, title: String, tab: AppTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 21, weight: selectedTab == tab ? .semibold : .regular))
                Text(title)
                    .font(.system(size: 12, weight: selectedTab == tab ? .semibold : .medium))
            }
            .foregroundStyle(
                selectedTab == tab
                ? Color(red: 0.16, green: 0.16, blue: 0.18)
                : Color(red: 0.68, green: 0.68, blue: 0.71)
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

private enum AppTab {
    case home
    case chat
    case profile
}

private struct HomeTabView: View {
    @ObservedObject var viewModel: HealthDashboardViewModel
    var useDemoData: Bool
    let onOpenChat: () -> Void

    private let cardColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 26) {
                headerSection
                dataSourcePill
                insightsSection
                summarySection
                extendedSummarySection
                conversationsSection
                askAISection
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 120)
        }
        .refreshable {
            await viewModel.bootstrap(useSimulation: useDemoData)
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color(red: 0.59, green: 0.59, blue: 0.62))

            Text("Good morning, Alex")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color(red: 0.12, green: 0.12, blue: 0.14))
        }
    }

    private var dataSourcePill: some View {
        Text(viewModel.statusMessage)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color(red: 0.45, green: 0.45, blue: 0.48))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(red: 0.96, green: 0.97, blue: 0.98))
            .clipShape(Capsule())
    }

    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Recent insights")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(red: 0.18, green: 0.18, blue: 0.2))

                Spacer()

                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color(red: 0.67, green: 0.67, blue: 0.7))
            }

            VStack(spacing: 0) {
                ForEach(Array(generatedInsights.enumerated()), id: \.offset) { index, item in
                    if index > 0 { divider }
                    insightRow(title: item.title, message: item.message)
                }
            }
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color(red: 0.91, green: 0.91, blue: 0.93), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private var generatedInsights: [(title: String, message: String)] {
        var out: [(String, String)] = []
        if let slp = sleepHoursValue, slp < 7 {
            out.append((
                "Sleep under a common 7h target",
                "You logged about \(String(format: "%.1f", slp))h of asleep time. Consider an earlier wind-down and consistent wake time."
            ))
        } else if let slp = sleepHoursValue, slp >= 7 {
            out.append((
                "Recovery window looks solid",
                "You logged about \(String(format: "%.1f", slp))h of asleep time in the last 24h — keep the rhythm."
            ))
        }
        if let rhr = metricValue(named: "Resting Heart Rate"), rhr < 60 {
            out.append((
                "Resting heart rate in a trained range",
                "Your latest resting HR is about \(Int(rhr)) bpm. If this is new, track how it lines up with sleep and load."
            ))
        } else if let hrv = metricValue(named: "Heart Rate Variability"), hrv < 30 {
            out.append((
                "HRV is on the lower side",
                "Latest HRV is around \(String(format: "%.0f", hrv)) ms. Recovery tools (sleep, light activity, stress breaks) can help nudge it up."
            ))
        }
        if let steps = metricValue(named: "Step Count"), steps < 4_000 {
            out.append((
                "Movement is light so far",
                "About \(Int(steps)) steps today — short walks or a 10-minute reset can move the dial."
            ))
        }
        if out.isEmpty {
            return [
                ("No strong signals yet", "Pull to refresh after you grant Apple Health access, or add data in the Health app."),
                ("Tip", "HRV and resting HR are easier to read when you wear a watch at night and keep sleep stages enabled."),
                ("Tip", "Turn on demo data in Profile if you are testing the UI in Simulator.")
            ]
        }
        if out.count > 3 { return Array(out.prefix(3)) }
        let more = [
            ("Local analysis", "These insights use only data on this device. Your on-device agent can add more on GX10."),
            ("Wearables", "Enable sleep stages in Apple Health for more accurate rest metrics.")
        ]
        var o = out
        for row in more where o.count < 3 { o.append(row) }
        return o
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today's summary")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(red: 0.18, green: 0.18, blue: 0.2))

                Spacer()

                Text("View all")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(red: 0.66, green: 0.66, blue: 0.69))
            }

            LazyVGrid(columns: cardColumns, spacing: 12) {
                summaryCard(
                    symbol: "heart",
                    title: "Heart rate",
                    valueText: heartRateValue,
                    unitText: "bpm",
                    detail: heartRateDetail,
                    dotColor: Color(red: 0.34, green: 0.78, blue: 0.65)
                )

                summaryCard(
                    symbol: "moon",
                    title: "Sleep",
                    valueText: sleepValue,
                    unitText: nil,
                    detail: sleepDetail,
                    dotColor: Color(red: 0.95, green: 0.66, blue: 0.07)
                )

                summaryCard(
                    symbol: "waveform.path.ecg",
                    title: "Activity",
                    valueText: stepsValue,
                    unitText: "steps",
                    detail: stepDetail,
                    dotColor: Color(red: 0.34, green: 0.78, blue: 0.65)
                )

                summaryCard(
                    symbol: "brain.head.profile",
                    title: "Stress",
                    valueText: stressValue,
                    unitText: nil,
                    detail: stressDetail,
                    dotColor: Color(red: 0.95, green: 0.66, blue: 0.07)
                )
            }
        }
    }

    private var extendedSummarySection: some View {
        VStack(alignment: .leading, spacing: 22) {
            LazyVGrid(columns: cardColumns, spacing: 12) {
                summaryCard(
                    symbol: "flame",
                    title: "Active energy",
                    valueText: activeEnergyValue,
                    unitText: "kcal",
                    detail: "Today, Apple Health",
                    dotColor: Color(red: 0.34, green: 0.78, blue: 0.65)
                )

                summaryCard(
                    symbol: "figure.strengthtraining.traditional",
                    title: "Workouts",
                    valueText: workoutCountValue,
                    unitText: "7d",
                    detail: "Sessions in last 7 days",
                    dotColor: Color(red: 0.34, green: 0.78, blue: 0.65)
                )
            }

            chartCard(
                title: "Heart rate",
                valueText: chartHeartRateValue,
                unitText: chartHeartRateSubtext,
                trailingText: "Today",
                chartHeight: 86
            ) {
                if viewModel.snapshot.heartRateLineNormalizedYs.count >= 2 {
                    NormalizedHeartLineShape(
                        yNorm: viewModel.snapshot.heartRateLineNormalizedYs
                    )
                    .stroke(Color(red: 0.46, green: 0.52, blue: 0.64), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 10)
                } else {
                    Text("Add heart rate samples in Health for an intraday line")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(red: 0.55, green: 0.55, blue: 0.58))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }

            chartCard(
                title: "Sleep this week",
                valueText: weekAvgSleepString,
                unitText: "avg hrs",
                trailingText: "7d",
                chartHeight: 120
            ) {
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(Array(viewModel.snapshot.weekSleep.enumerated()), id: \.offset) { _, d in
                        VStack(spacing: 6) {
                            if let h = d.hours, h > 0 {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color(red: 0.46, green: 0.52, blue: 0.64))
                                    .frame(height: CGFloat(min(h / 10, 1)) * 44 + 4)
                            } else {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color(red: 0.9, green: 0.91, blue: 0.93))
                                    .frame(height: 4)
                            }
                            Text(d.weekdayLabel)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color(red: 0.67, green: 0.67, blue: 0.7))
                            Text(sleepLabelShort(d.hours))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color(red: 0.5, green: 0.5, blue: 0.53))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.bottom, 4)
            }
        }
    }

    private func sleepLabelShort(_ h: Double?) -> String {
        guard let h, h > 0 else { return "—" }
        return String(format: "%.1fh", h)
    }

    private var conversationsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Conversations")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(red: 0.18, green: 0.18, blue: 0.2))

                Spacer()

                Text("See all")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(red: 0.66, green: 0.66, blue: 0.69))
            }

            VStack(spacing: 0) {
                conversationRow(title: "Why did my HRV drop yesterday?", subtitle: "Today, 9:24 AM")
                divider
                conversationRow(title: "Help me plan a recovery week", subtitle: "Yesterday")
                divider
                conversationRow(title: "Is 6 hours of sleep enough?", subtitle: "Apr 23")
                divider
                conversationRow(title: "Best stretches for desk work", subtitle: "Apr 21")
            }
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color(red: 0.91, green: 0.91, blue: 0.93), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private var askAISection: some View {
        Button {
            onOpenChat()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .semibold))
                Text("Ask AI")
                    .font(.system(size: 18, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 88)
            .background(Color(red: 0.11, green: 0.11, blue: 0.12))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color(red: 0.93, green: 0.93, blue: 0.95))
            .frame(height: 1)
    }

    private func insightRow(title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Color(red: 0.35, green: 0.8, blue: 0.72))
                .frame(width: 7, height: 7)
                .padding(.top, 7)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(red: 0.2, green: 0.2, blue: 0.22))

                Text(message)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(red: 0.49, green: 0.49, blue: 0.52))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }

    private func summaryCard(
        symbol: String,
        title: String,
        valueText: String,
        unitText: String?,
        detail: String,
        dotColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                } icon: {
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .medium))
                }
                .foregroundStyle(Color(red: 0.49, green: 0.49, blue: 0.52))

                Spacer()

                Circle()
                    .fill(dotColor)
                    .frame(width: 7, height: 7)
            }

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(valueText)
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(Color(red: 0.14, green: 0.14, blue: 0.16))

                if let unitText {
                    Text(unitText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(red: 0.62, green: 0.62, blue: 0.65))
                }
            }

            Text(detail)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color(red: 0.67, green: 0.67, blue: 0.7))
        }
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .leading)
        .padding(16)
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color(red: 0.91, green: 0.91, blue: 0.93), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func chartCard<Content: View>(
        title: String,
        valueText: String,
        unitText: String,
        trailingText: String,
        chartHeight: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color(red: 0.46, green: 0.46, blue: 0.48))

                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(valueText)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(Color(red: 0.14, green: 0.14, blue: 0.16))
                        Text(unitText)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(red: 0.66, green: 0.66, blue: 0.69))
                    }
                }

                Spacer()

                Text(trailingText)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(red: 0.66, green: 0.66, blue: 0.69))
            }

            content()
                .frame(maxWidth: .infinity)
                .frame(height: chartHeight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color(red: 0.91, green: 0.91, blue: 0.93), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func conversationRow(title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "bubble.left")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Color(red: 0.72, green: 0.72, blue: 0.74))

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color(red: 0.16, green: 0.16, blue: 0.18))

                Text(subtitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 0.67, green: 0.67, blue: 0.69))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(red: 0.84, green: 0.84, blue: 0.86))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 20)
    }

    private var heartRateValue: String {
        if let v = metricValue(named: "Resting Heart Rate") { return String(Int(v.rounded())) }
        if let v = metricValue(named: "Walking HR average") { return String(Int(v.rounded())) }
        if let v = metricValue(named: "Heart Rate (latest)") { return String(Int(v.rounded())) }
        return "—"
    }

    private var heartRateDetail: String {
        if metricValue(named: "Resting Heart Rate") != nil { return "Resting (HealthKit)" }
        if let v = metricValue(named: "Heart Rate (latest)") { return "Latest: \(Int(v)) bpm" }
        return "No RHR in Health"
    }

    private var sleepHoursValue: Double? {
        metricValue(named: "Sleep (last 24h asleep)")
    }

    private var sleepValue: String {
        guard let hours = sleepHoursValue, hours > 0 else { return "—" }
        let totalMinutes = Int((hours * 60).rounded())
        let hourPart = totalMinutes / 60
        let minutePart = totalMinutes % 60
        return "\(hourPart)h \(minutePart)m"
    }

    private var sleepDetail: String {
        guard let h = sleepHoursValue, h > 0 else { return "No sleep stage data" }
        if h < 7 { return "Below a common 7h target" }
        return "In range for many users"
    }

    private var stepsValue: String {
        guard let steps = metricValue(named: "Step Count"), steps > 0 else { return "—" }
        return Int(steps).formatted(.number.grouping(.automatic))
    }

    private var stepDetail: String {
        let goal: Double = 10_000
        guard let steps = metricValue(named: "Step Count") else { return "No step data" }
        let p = min(100, max(0, (steps / goal) * 100))
        return String(format: "%.0f%% of a 10k step goal", p)
    }

    private var stressValue: String {
        guard let hrv = metricValue(named: "Heart Rate Variability") else { return "—" }
        return String(Int(max(18, min(82, 80 - hrv)).rounded()))
    }

    private var stressDetail: String {
        guard let hrv = metricValue(named: "Heart Rate Variability") else { return "HRV not available" }
        if hrv < 30 { return "HRV is relatively low" }
        if hrv < 50 { return "HRV in a moderate range" }
        return "HRV looks comfortable"
    }

    private var activeEnergyValue: String {
        guard let v = metricValue(named: "Active Energy"), v > 0 else { return "—" }
        return String(Int(v.rounded()))
    }

    private var workoutCountValue: String {
        guard let w = metricValue(named: "Workouts (7d count)"), w >= 0 else { return "—" }
        return String(Int(w.rounded()))
    }

    private var chartHeartRateValue: String {
        if let a = metricValue(named: "Heart Rate (today avg)") { return String(Int(a.rounded())) }
        if let a = metricValue(named: "Resting Heart Rate") { return String(Int(a.rounded())) }
        return "—"
    }

    private var chartHeartRateSubtext: String {
        if metricValue(named: "Heart Rate (today avg)") != nil { return "avg bpm" }
        if metricValue(named: "Resting Heart Rate") != nil { return "resting" }
        return "bpm"
    }

    private var weekAvgSleepString: String {
        if let a = viewModel.snapshot.averageSleepThisWeek { return String(format: "%.1f", a) }
        return "—"
    }

    private func metricValue(named title: String) -> Double? {
        viewModel.snapshot.metrics.first(where: { $0.title == title })?.value
    }
}

private struct ChatTabView: View {
    @State private var draftMessage = ""

    private let messages: [ChatMessage] = [
        ChatMessage(role: .assistant, text: "I noticed your HRV dropped yesterday while your sleep duration also trended lower. Want me to break down likely causes?"),
        ChatMessage(role: .user, text: "Yes, and compare it with my resting heart rate too."),
        ChatMessage(role: .assistant, text: "Your resting heart rate moved up slightly overnight, which often pairs with reduced recovery. The strongest signal here is short sleep plus elevated stress midday."),
        ChatMessage(role: .user, text: "What should I do today?"),
        ChatMessage(role: .assistant, text: "Keep training light, add a 20-minute walk after lunch, and aim for an earlier bedtime tonight.")
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("Chat log")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(Color(red: 0.12, green: 0.12, blue: 0.14))
                        Spacer()
                    }
                    .padding(.bottom, 4)

                    ForEach(messages) { message in
                        chatBubble(message)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }

            HStack(spacing: 12) {
                TextField("Ask your health agent something...", text: $draftMessage)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .background(Color(red: 0.96, green: 0.96, blue: 0.97))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Button {
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(Color(red: 0.11, green: 0.11, blue: 0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 110)
            .background(Color.white)
        }
    }

    private func chatBubble(_ message: ChatMessage) -> some View {
        VStack(alignment: message.role == .assistant ? .leading : .trailing, spacing: 8) {
            Text(message.role.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(red: 0.67, green: 0.67, blue: 0.69))

            Text(message.text)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(message.role == .assistant ? Color(red: 0.14, green: 0.14, blue: 0.16) : .white)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: message.role == .assistant ? .leading : .trailing)
                .background(message.role == .assistant ? Color(red: 0.97, green: 0.97, blue: 0.98) : Color(red: 0.11, green: 0.11, blue: 0.12))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: message.role == .assistant ? .leading : .trailing)
    }
}

private struct ProfileTabView: View {
    @ObservedObject var viewModel: HealthDashboardViewModel
    @Binding var useDemoData: Bool

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 16) {
                        Circle()
                            .fill(Color(red: 0.95, green: 0.95, blue: 0.97))
                            .frame(width: 72, height: 72)
                            .overlay {
                                Text("A")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundStyle(Color(red: 0.14, green: 0.14, blue: 0.16))
                            }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Alex Carter")
                                .font(.system(size: 28, weight: .bold))
                            Text("Peer-to-peer recovery profile")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color(red: 0.6, green: 0.6, blue: 0.63))
                        }
                    }

                    Text("This profile controls what your local health agent can use when matching you against similar anonymized cases on the network.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color(red: 0.46, green: 0.46, blue: 0.5))
                }

                Toggle("Use demo health data (no HealthKit)", isOn: $useDemoData)
                    .font(.system(size: 16, weight: .semibold))
                    .tint(Color(red: 0.11, green: 0.11, blue: 0.12))
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color(red: 0.91, green: 0.91, blue: 0.93), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                profileCard(title: "Vitals (from Health when available)") {
                    profileRow(label: "Age", value: viewModel.snapshot.userProfile.ageDescription)
                    profileRow(label: "Biological sex", value: viewModel.snapshot.userProfile.sexDescription)
                    profileRow(label: "Height", value: viewModel.snapshot.userProfile.heightDescription)
                    profileRow(label: "Weight", value: viewModel.snapshot.userProfile.weightDescription)
                }

                profileCard(title: "Conditions") {
                    profileTagRow(tags: ["Mild hypertension", "Desk-heavy work", "Marathon training"])
                }

                profileCard(title: "Agent settings") {
                    profileRow(label: "Anonymized peer search", value: "Enabled")
                    profileRow(label: "Local GX10 sync", value: "Online")
                    profileRow(label: "Preferred goal", value: "Recovery + sleep")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 120)
        }
    }

    private func profileCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(red: 0.18, green: 0.18, blue: 0.2))

            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color(red: 0.91, green: 0.91, blue: 0.93), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func profileRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color(red: 0.5, green: 0.5, blue: 0.53))
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(red: 0.14, green: 0.14, blue: 0.16))
        }
    }

    private func profileTagRow(tags: [String]) -> some View {
        FlowLayout(tags: tags)
    }
}

private struct ChatMessage: Identifiable {
    let id = UUID()
    let role: ChatRole
    let text: String
}

private enum ChatRole {
    case assistant
    case user

    var title: String {
        switch self {
        case .assistant:
            return "PeerHealth AI"
        case .user:
            return "You"
        }
    }
}

private struct FlowLayout: View {
    let tags: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ForEach(Array(tags.prefix(2)), id: \.self) { tag in
                    tagView(tag)
                }
            }

            if tags.count > 2 {
                HStack(spacing: 10) {
                    ForEach(Array(tags.dropFirst(2)), id: \.self) { tag in
                        tagView(tag)
                    }
                }
            }
        }
    }

    private func tagView(_ tag: String) -> some View {
        Text(tag)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color(red: 0.18, green: 0.18, blue: 0.2))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(red: 0.96, green: 0.96, blue: 0.97))
            .clipShape(Capsule())
    }
}

/// Renders a polyline of normalized 0...1 y-values across the view width.
private struct NormalizedHeartLineShape: Shape {
    var yNorm: [CGFloat]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard yNorm.count >= 2 else { return path }
        let n = yNorm.count - 1
        for (i, yn) in yNorm.enumerated() {
            let yClamped = min(1, max(0, yn))
            let x = rect.minX + rect.width * CGFloat(i) / CGFloat(n)
            let y = rect.maxY - yClamped * rect.height
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }
}

#Preview {
    ContentView()
}
