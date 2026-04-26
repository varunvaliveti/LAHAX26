//
//  ReadinessOrb.swift
//  PeerHealth
//

import SwiftUI

struct ReadinessOrb: View {
    let score: Int
    var size: CGFloat = 220
    var trend: String = "↑ trending up"

    @State private var draw: CGFloat = 0

    private var pct: CGFloat {
        CGFloat(min(100, max(0, score))) / 100.0
    }

    private var stroke: CGFloat { 4 }

    private var innerSize: CGFloat {
        size - stroke * 4 - 6
    }

    private let arcGradient = AngularGradient(
        gradient: Gradient(stops: [
            .init(color: Color(red: 1.0,  green: 0.42, blue: 0.36), location: 0.0),
            .init(color: Color(red: 0.77, green: 0.66, blue: 1.0),  location: 0.5),
            .init(color: Color(red: 0.31, green: 0.82, blue: 0.77), location: 1.0)
        ]),
        center: .center,
        startAngle: .degrees(-90),
        endAngle: .degrees(270)
    )

    var body: some View {
        ZStack {
            // Jelly inside the dome
            JellyDisc(blur: 18, intensity: 0.95, speed: 0.8)
                .frame(width: innerSize + 40, height: innerSize + 40)
                .frame(width: innerSize, height: innerSize)
                .clipShape(Circle())

            // Glass dome
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.55),
                            Color.white.opacity(0.05),
                            Color.white.opacity(0)
                        ],
                        center: UnitPoint(x: 0.35, y: 0.30),
                        startRadius: 0,
                        endRadius: innerSize * 0.7
                    )
                )
                .overlay(
                    Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 0.5)
                )
                .frame(width: innerSize, height: innerSize)
                .shadow(color: .black.opacity(0.12), radius: 30, x: 0, y: 30)

            // Dashed unfilled track
            Circle()
                .stroke(
                    Color.black.opacity(0.06),
                    style: StrokeStyle(lineWidth: stroke, lineCap: .round, dash: [2, 5])
                )
                .frame(width: size - stroke - 2, height: size - stroke - 2)

            // Filled progress arc
            Circle()
                .trim(from: 0, to: pct * draw)
                .stroke(
                    arcGradient,
                    style: StrokeStyle(lineWidth: stroke, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: size - stroke - 2, height: size - stroke - 2)
                .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 1)

            // Head dot at end of arc
            if draw > 0.05 {
                let angle = Double(pct * draw) * 2 * .pi - .pi / 2
                let radius = (size - stroke - 2) / 2
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.15), lineWidth: 0.5))
                    .frame(width: stroke / 1.6 * 2, height: stroke / 1.6 * 2)
                    .offset(x: cos(angle) * radius, y: sin(angle) * radius)
            }

            // Center label
            VStack(spacing: 2) {
                Text("READINESS")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(Color.black.opacity(0.5))
                Text("\(score)")
                    .font(.system(size: 64, weight: .bold))
                    .tracking(-2)
                    .foregroundStyle(Color(red: 0.07, green: 0.07, blue: 0.09))
                    .padding(.top, 2)
                Text(trend)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 0.20, green: 0.78, blue: 0.35))
                    .padding(.top, 2)
            }
            .allowsHitTesting(false)
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.easeOut(duration: 1.1)) {
                draw = 1.0
            }
        }
    }
}
