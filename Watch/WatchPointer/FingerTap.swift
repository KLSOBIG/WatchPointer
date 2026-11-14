import CoreMotion
import Foundation

/// Finger taps felt at the wrist, on any watch: tap your thumb against your index finger once, sharply.
///
/// A tap shakes the watch for a few hundredths of a second; pointing moves it slowly. So: keep only the fast
/// part of the acceleration (high-pass), and call it a tap when that jumps well above the usual jitter,
/// out of quiet, and dies down again within 60 ms, while the arm is neither swinging nor pushing. Decided 60 ms after the peak.
struct FingerTapDetector {
    /// What a peak looked like. Every clear bump is reported (for the meter); `tap` says if it counted.
    struct Event {
        let time: TimeInterval // when the shake peaked, on the motion clock
        let peak: Double       // in g
        let tap: Bool
    }

    /// Sensitivity 1…3: smallest peak (g) that can count, and how many times the usual jitter it must be.
    static func threshold(level: Int) -> (minPeak: Double, overNoise: Double) {
        switch level {
        case 1: (0.15, 8)
        case 2: (0.10, 6)
        default: (0.06, 5)
        }
    }

    private struct Sample { let t: TimeInterval; let m: Double; let raw: Double; let spin: Double }

    private static let size = 24  // samples kept (240 ms at 100 Hz)
    private static let wait = 6   // samples after the peak before deciding (60 ms)
    private static let cutoff = 8.0 // Hz: slower than this is pointing, faster is a tap

    private var buffer: [Sample] = []
    private var fast = (x: 0.0, y: 0.0, z: 0.0)
    private var previous: CMAcceleration?
    private var noise = 0.01      // usual size of the fast part, in g
    private var lastTap = -1.0

    mutating func add(time t: TimeInterval, dt: Double, acceleration a: CMAcceleration,
                      spin: Double, level: Int) -> Event? {
        // One-pole high-pass on each axis.
        if let p = previous, dt > 0 {
            let rc = 1 / (2 * .pi * Self.cutoff)
            let k = rc / (rc + dt)
            fast = (k * (fast.x + a.x - p.x), k * (fast.y + a.y - p.y), k * (fast.z + a.z - p.z))
        }
        previous = a
        let m = (fast.x * fast.x + fast.y * fast.y + fast.z * fast.z).squareRoot()
        if m < noise * 3 { noise = max(noise + (m - noise) * 0.01, 0.005) } // about a second to settle; spikes ignored

        buffer.append(Sample(t: t, m: m, raw: (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot(), spin: spin))
        if buffer.count > Self.size { buffer.removeFirst() }
        guard buffer.count == Self.size else { return nil }

        let c = Self.size - 1 - Self.wait
        let peak = buffer[c].m
        guard peak > 0.03 else { return nil }
        // A peak: the biggest from 60 ms before to 60 ms after.
        for i in (c - Self.wait)..<Self.size where i != c {
            if (i < c) ? (buffer[i].m > peak) : (buffer[i].m >= peak) { return nil }
        }

        let (minPeak, overNoise) = Self.threshold(level: level)
        let before = buffer[0...(c - 4)]  // up to 40 ms before the peak
        let quietBefore = before.map(\.m).max()! < peak * 0.4
        let quietAfter = max(buffer[Self.size - 1].m, buffer[Self.size - 2].m) < peak * 0.4
        let armStill = before.map(\.spin).reduce(0, +) / Double(before.count) < 2.0 // rad/s
        // A tap barely moves the arm; starting or stopping a move pushes it for a good part of the window.
        let armSteady = buffer.map(\.raw).reduce(0, +) / Double(Self.size) < 0.12 // g
        let rested = buffer[c].t - lastTap > 0.2
        let tap = peak > max(minPeak, noise * overNoise) && quietBefore && quietAfter && armStill && armSteady && rested
        if tap { lastTap = buffer[c].t }
        return Event(time: buffer[c].t, peak: peak, tap: tap)
    }
}

/// Touching the watch (the screen or the Crown, with your other hand) shakes it like a finger tap.
/// Finger taps are ignored while touching and just after.
enum Touch {
    private static var active = false
    private static var last = 0.0

    static func mark(_ down: Bool) {
        active = down
        last = ProcessInfo.processInfo.systemUptime
    }

    static var recent: Bool { active || ProcessInfo.processInfo.systemUptime - last < 0.3 }
}
