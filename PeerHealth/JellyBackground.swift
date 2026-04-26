//
//  JellyBackground.swift
//  PeerHealth
//

import SwiftUI

enum JellyPalette {
    case iridescent, cool, warm, mono

    struct Stop {
        let color: Color
        let x: CGFloat
        let y: CGFloat
        let r: CGFloat
    }

    var stops: [Stop] {
        switch self {
        case .iridescent:
            return [
                Stop(color: Color(red: 1.0,  green: 0.42, blue: 0.36), x: 30, y: 35, r: 60),
                Stop(color: Color(red: 0.31, green: 0.82, blue: 0.77), x: 70, y: 60, r: 55),
                Stop(color: Color(red: 0.77, green: 0.66, blue: 1.0),  x: 50, y: 30, r: 50),
                Stop(color: Color(red: 1.0,  green: 0.69, blue: 0.53), x: 25, y: 70, r: 50),
                Stop(color: Color(red: 1.0,  green: 0.88, blue: 0.40), x: 75, y: 25, r: 40)
            ]
        case .cool:
            return [
                Stop(color: Color(red: 0.36, green: 0.55, blue: 1.0),  x: 30, y: 35, r: 60),
                Stop(color: Color(red: 0.31, green: 0.82, blue: 0.77), x: 70, y: 60, r: 55),
                Stop(color: Color(red: 0.77, green: 0.66, blue: 1.0),  x: 50, y: 30, r: 55),
                Stop(color: Color(red: 0.53, green: 0.85, blue: 1.0),  x: 25, y: 70, r: 50),
                Stop(color: Color(red: 0.63, green: 0.91, blue: 0.85), x: 75, y: 25, r: 45)
            ]
        case .warm:
            return [
                Stop(color: Color(red: 1.0,  green: 0.36, blue: 0.48), x: 30, y: 35, r: 60),
                Stop(color: Color(red: 1.0,  green: 0.60, blue: 0.40), x: 70, y: 60, r: 55),
                Stop(color: Color(red: 1.0,  green: 0.82, blue: 0.40), x: 50, y: 30, r: 55),
                Stop(color: Color(red: 1.0,  green: 0.49, blue: 0.71), x: 25, y: 70, r: 50),
                Stop(color: Color(red: 1.0,  green: 0.69, blue: 0.53), x: 75, y: 25, r: 45)
            ]
        case .mono:
            return [
                Stop(color: Color(red: 0,    green: 0,    blue: 0),    x: 30, y: 35, r: 60),
                Stop(color: Color(red: 0.20, green: 0.20, blue: 0.20), x: 70, y: 60, r: 55),
                Stop(color: Color(red: 0.40, green: 0.40, blue: 0.40), x: 50, y: 30, r: 50),
                Stop(color: Color(red: 0.10, green: 0.10, blue: 0.10), x: 25, y: 70, r: 50),
                Stop(color: Color(red: 0.27, green: 0.27, blue: 0.27), x: 75, y: 25, r: 40)
            ]
        }
    }
}

/// Animated full-bleed iridescent metaball atmosphere. Renders 5 radial gradient
/// blobs that wobble on Lissajous curves, blended with `.screen` and globally blurred.
/// Pass `pointer` (normalized 0..1 in the screen's coordinate space) to bias the
/// blobs toward the user's finger.
struct JellyBackground: View {
    var palette: JellyPalette = .iridescent
    var blur: CGFloat = 70
    var intensity: CGFloat = 1.0
    var speed: Double = 0.7
    var opacity: Double = 0.85
    var pointer: UnitPoint? = nil

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate * speed
            GeometryReader { geo in
                ZStack {
                    ForEach(Array(palette.stops.enumerated()), id: \.offset) { index, stop in
                        blob(stop: stop, t: t, index: index, size: geo.size)
                            .blendMode(index == 0 ? .normal : .screen)
                    }
                }
                .compositingGroup()
                .blur(radius: blur)
                .saturation(1.5)
                .opacity(opacity)
            }
            .allowsHitTesting(false)
        }
    }

    private func blob(stop: JellyPalette.Stop, t: Double, index: Int, size: CGSize) -> some View {
        let phase = Double(index) * 1.7
        let wx = CGFloat(sin(t * 0.5 + phase)) * 18
        let wy = CGFloat(cos(t * 0.4 + phase * 1.3)) * 18

        var px: CGFloat = 0
        var py: CGFloat = 0
        if let p = pointer {
            let nx = p.x * 100
            let ny = p.y * 100
            px = (nx - stop.x) * 0.30
            py = (ny - stop.y) * 0.30
        }

        let cx = (stop.x + wx + px) / 100 * size.width
        let cy = (stop.y + wy + py) / 100 * size.height
        let baseR = stop.r + CGFloat(sin(t * 0.6 + phase)) * 8
        let r = baseR * intensity / 100 * max(size.width, size.height) * 1.2

        return RadialGradient(
            colors: [stop.color, stop.color.opacity(0)],
            center: UnitPoint(x: cx / size.width, y: cy / size.height),
            startRadius: 0,
            endRadius: r
        )
        .frame(width: size.width * 1.4, height: size.height * 1.4)
        .position(x: size.width / 2, y: size.height / 2)
    }
}

/// Wraps a screen's content and tracks the touch point, exposing it as a normalized
/// UnitPoint so a `JellyBackground` can react. The tracker uses a low-priority
/// drag gesture so taps, scrolls, and text input still work.
struct PointerTrackingScreen<Content: View>: View {
    @ViewBuilder var content: (UnitPoint?) -> Content

    @State private var pointer: UnitPoint? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack { content(pointer) }
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in
                            let nx = max(0, min(1, value.location.x / max(1, geo.size.width)))
                            let ny = max(0, min(1, value.location.y / max(1, geo.size.height)))
                            pointer = UnitPoint(x: nx, y: ny)
                        }
                        .onEnded { _ in
                            withAnimation(.easeOut(duration: 0.6)) {
                                pointer = nil
                            }
                        }
                )
        }
    }
}

/// Fixed-size jelly disc, used inside avatars and the readiness orb.
struct JellyDisc: View {
    var palette: JellyPalette = .iridescent
    var blur: CGFloat = 18
    var intensity: CGFloat = 0.95
    var speed: Double = 0.8

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate * speed
            GeometryReader { geo in
                ZStack {
                    ForEach(Array(palette.stops.enumerated()), id: \.offset) { index, stop in
                        blob(stop: stop, t: t, index: index, size: geo.size)
                            .blendMode(index == 0 ? .normal : .screen)
                    }
                }
                .compositingGroup()
                .blur(radius: blur)
                .saturation(1.4)
            }
        }
    }

    private func blob(stop: JellyPalette.Stop, t: Double, index: Int, size: CGSize) -> some View {
        let phase = Double(index) * 1.7
        let wx = CGFloat(sin(t * 0.5 + phase)) * 12
        let wy = CGFloat(cos(t * 0.4 + phase * 1.3)) * 12
        let cx = (stop.x + wx) / 100 * size.width
        let cy = (stop.y + wy) / 100 * size.height
        let baseR = stop.r + CGFloat(sin(t * 0.6 + phase)) * 6
        let r = baseR * intensity / 100 * max(size.width, size.height) * 1.4

        return RadialGradient(
            colors: [stop.color, stop.color.opacity(0)],
            center: UnitPoint(x: cx / size.width, y: cy / size.height),
            startRadius: 0,
            endRadius: r
        )
        .frame(width: size.width * 1.4, height: size.height * 1.4)
        .position(x: size.width / 2, y: size.height / 2)
    }
}
