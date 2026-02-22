import SwiftUI
#if os(macOS)
import AppKit
#endif

/// A custom speed slider (0.5x–3.0x) with divots at 1x/2x/3x, snap detents, and haptic feedback.
/// Built from scratch to guarantee label alignment with the track.
public struct SpeedSlider: View {
    @Binding var speed: Float

    public init(speed: Binding<Float>) {
        self._speed = speed
    }

    private let minVal: Float = 0.5
    private let maxVal: Float = 3.0
    private let step: Float = 0.1
    private let detents: [Float] = [1.0, 2.0, 3.0]
    private let snapRadius: Float = 0.15
    private let trackHeight: CGFloat = 4
    private let thumbSize: CGFloat = 18
    private let divotSize: CGFloat = 6

    private func fraction(for value: Float) -> CGFloat {
        CGFloat((value - minVal) / (maxVal - minVal))
    }

    private func value(for fraction: CGFloat) -> Float {
        let clamped = min(max(fraction, 0), 1)
        let raw = minVal + Float(clamped) * (maxVal - minVal)
        return (raw / step).rounded() * step
    }

    public var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let trackWidth = geo.size.width
                let frac = fraction(for: speed)
                let thumbX = frac * trackWidth

                ZStack(alignment: .leading) {
                    // Track background
                    Capsule()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(height: trackHeight)

                    // Filled portion
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: max(thumbX, 0), height: trackHeight)

                    // Divots at detent positions
                    ForEach(detents, id: \.self) { detent in
                        let dx = fraction(for: detent) * trackWidth
                        let isActive = speed >= detent
                        Circle()
                            .fill(isActive ? Color.accentColor : Color.secondary.opacity(0.5))
                            .frame(width: divotSize, height: divotSize)
                            .position(x: dx, y: thumbSize / 2)
                    }

                    // Thumb
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                        .frame(width: thumbSize, height: thumbSize)
                        .offset(x: thumbX - thumbSize / 2)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { drag in
                                    let newFrac = drag.location.x / trackWidth
                                    let newVal = value(for: newFrac)
                                    if newVal != speed {
                                        let oldSpeed = speed
                                        speed = newVal
                                        checkDetent(old: oldSpeed, new: newVal)
                                    }
                                }
                                .onEnded { drag in
                                    snapToNearestDetent()
                                }
                        )
                }
                .frame(height: thumbSize)
            }
            .frame(height: thumbSize)

            // Tick labels
            GeometryReader { geo in
                let trackWidth = geo.size.width
                ForEach(detents, id: \.self) { detent in
                    let x = fraction(for: detent) * trackWidth
                    Text("\(Int(detent))x")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .position(x: x, y: 4)
                }
            }
            .frame(height: 12)
        }
    }

    private func checkDetent(old: Float, new: Float) {
        for detent in detents {
            // Haptic when crossing a detent boundary
            if abs(new - detent) < 0.06 && abs(old - detent) >= 0.06 {
                playDetentHaptic()
            }
        }
    }

    private func snapToNearestDetent() {
        for detent in detents {
            if abs(speed - detent) <= snapRadius {
                speed = detent
                playDetentHaptic()
                return
            }
        }
    }

    private func playDetentHaptic() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        #endif
    }
}
