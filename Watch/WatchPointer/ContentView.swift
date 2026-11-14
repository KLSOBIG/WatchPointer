import SwiftUI

/// Mac scroll distance, in pixels, per unit of Crown turn. Higher = faster scrolling.
private let crownPixels = 100.0

/// A remote you use without looking: one big pad, three buttons in fixed places, haptics for feedback.
struct ContentView: View {
    @StateObject private var pointer = Pointer()
    @State private var crown = 0.0
    @FocusState private var crownFocused: Bool
    @State private var clicks = 0
    @State private var centers = 0
    @State private var confirmUnpair = false
    @State private var unpairTitle = ""

    var body: some View {
        NavigationStack {
            remote
                .toolbar {
                    if pointer.connected {
                        // Top-left, next to the clock: which Mac this is, and the way to unpair it.
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                unpairTitle = pointer.pairedName ?? "Mac" // fixed while the dialog is up
                                confirmUnpair = true
                            } label: { Image(systemName: "laptopcomputer") }
                        }
                        // Top-right: finger taps (any watch). Each press: off → low → medium → high sensitivity.
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                pointer.fingerLevel = (pointer.fingerLevel + 1) % 4
                            } label: {
                                HStack(spacing: 1) {
                                    Image(systemName: "hand.point.up.left")
                                    if pointer.fingerLevel > 0 {
                                        Text("\(pointer.fingerLevel)").font(.system(size: 12, weight: .bold))
                                    }
                                }
                                .foregroundStyle(pointer.fingerLevel > 0 ? .orange : .white)
                            }
                        }
                    }
                }
                .confirmationDialog(unpairTitle, isPresented: $confirmUnpair, titleVisibility: .visible) {
                    Button("Unpair", role: .destructive) {
                        // Unpair once the dialog has closed; changing the screen under it made it pop up a second time.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { pointer.forget() }
                    }
                }
        }
    }

    private var remote: some View {
        Group {
            if pointer.connected {
                VStack(spacing: 6) {
                    ClickPad(paused: pointer.paused, clicks: $clicks, pointer: pointer)
                        .frame(maxHeight: .infinity)
                    HStack(spacing: 6) {
                        PadButton(symbol: "contextualmenu.and.cursorarrow") {
                            clicks += 1
                            // Buttons fire on release; a press lasts about this long, so this is roughly touch-down.
                            pointer.send(.rightClick, at: ProcessInfo.processInfo.systemUptime - 0.12)
                        }
                        PadButton(symbol: "scope") {
                            centers += 1
                            pointer.center()
                        }
                        PadButton(symbol: pointer.paused ? "play.fill" : "pause.fill", tint: pointer.paused ? .orange : .white) {
                            pointer.togglePause()
                        }
                    }
                    .frame(height: 52)
                }
                .padding(.horizontal, 4)
                .transition(.opacity)
            } else if let name = pointer.pairedName {
                WaitingForMac(name: name) { pointer.forget() }
                    .transition(.opacity)
            } else {
                PairList(found: pointer.found) { pointer.pair($0) }
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .animation(.smooth(duration: 0.3), value: pointer.connected)
        // The Crown only reaches the focused view, so keep focus here rather than on a button.
        .focusable()
        .focused($crownFocused)
        .digitalCrownRotation($crown)
        .onChange(of: crown) { old, new in
            Touch.mark(false) // turning the Crown shakes the watch too
            pointer.scroll(by: (new - old) * crownPixels)
        }
        .onAppear { crownFocused = true }
        .onChange(of: pointer.connected) { crownFocused = true }
        .sensoryFeedback(.impact(weight: .light), trigger: clicks)
        .sensoryFeedback(.success, trigger: centers)
        .sensoryFeedback(.selection, trigger: pointer.paused)
        .sensoryFeedback(trigger: pointer.connected) { _, now in now ? .start : .stop }
    }
}

/// Not paired yet: every Mac running the receiver nearby, each with a Pair button.
private struct PairList: View {
    let found: [FoundMac]
    let pair: (FoundMac) -> Void

    var body: some View {
        if found.isEmpty {
            Image(systemName: "laptopcomputer")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
                .symbolEffect(.pulse)
        } else {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(found) { mac in
                        Button { pair(mac) } label: {
                            HStack(spacing: 8) {
                                Text(mac.name)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("Pair")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(.white, in: Capsule())
                            }
                            .font(.system(size: 15, weight: .medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(minHeight: 52)
                            .background(Color(white: 0.16), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(PressStyle())
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }
}

/// Paired, but that Mac isn't connected right now (receiver closed or out of range). Connects by itself when it's back.
private struct WaitingForMac: View {
    let name: String
    let forget: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "laptopcomputer")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
                .symbolEffect(.pulse)
            Text(name)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color(white: 0.6))
                .lineLimit(1)
            Spacer()
            Button(action: forget) {
                Text("Forget")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color(white: 0.16), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(PressStyle())
        }
        .padding(.horizontal, 4)
    }
}

/// Tap = click. Hold = grab (mouse down); point to move; let go to drop.
/// Watch on the wrist, Double Tap (pinch twice): click. Again in the same spot: grab. Point, Double Tap: drop.
/// Finger taps (any watch, when on): the same, with one sharp thumb-on-finger tap in place of each Double Tap.
private struct ClickPad: View {
    let paused: Bool
    @Binding var clicks: Int
    @ObservedObject var pointer: Pointer

    @State private var pressing = false
    @State private var dragging = false
    @State private var holdTimer: Timer?
    @State private var touchDown: TimeInterval = 0
    /// The last Double Tap click: when, and where the watch pointed. A second one here soon after grabs.
    @State private var lastPinch: (time: TimeInterval, left: Double, up: Double)?

    /// `at`: when the fingers met, on the motion clock.
    private func pinched(at: TimeInterval) {
        guard !paused, !pressing else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if dragging {
            dragging = false
            pointer.send(.drag, 0, at: at)
            return
        }
        let aim = pointer.aimDegrees
        if let last = lastPinch, now - last.time < pinchGrabWindow,
           abs(aim.left - last.left) < pinchGrabSlack, abs(aim.up - last.up) < pinchGrabSlack {
            lastPinch = nil
            dragging = true
            pointer.send(.drag, 1, at: at)
            return
        }
        lastPinch = (now, aim.left, aim.up)
        clicks += 1
        pointer.send(.leftClick, at: at)
    }

    private var fill: Color {
        if dragging { return .white }
        if paused { return Color.orange.opacity(0.25) }
        return Color(white: pressing ? 0.28 : 0.16)
    }

    private var symbol: String { dragging ? "hand.raised.fill" : paused ? "pause.fill" : "cursorarrow.click" }

    var body: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(fill)
            // Double Tap only reaches a Button, so one sits behind the pad (covered, never touched).
            // Off while finger taps are on: a Double Tap is two finger taps, and would count twice.
            .background {
                if pointer.fingerLevel == 0 {
                    Button("Click") { pinched(at: ProcessInfo.processInfo.systemUptime - pinchDelay) }
                        .handGestureShortcut(.primaryAction)
                        .accessibilityHidden(true)
                }
            }
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(dragging ? .black : paused ? .orange : Color(white: 0.55))
                    .contentTransition(.symbolEffect(.replace))
            }
            .overlay(alignment: .bottom) {
                if pointer.fingerLevel > 0 { FingerMeter(peak: pointer.fingerPeak, level: pointer.fingerLevel, dark: dragging) }
            }
            .onChange(of: pointer.fingerTaps) { pinched(at: pointer.lastFingerTap - 0.02) } // just as the shake began
            .scaleEffect(pressing && !dragging ? 0.98 : 1)
            .animation(.smooth(duration: 0.15), value: pressing)
            .animation(.smooth(duration: 0.2), value: dragging)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressing else { return }
                        pressing = true
                        Touch.mark(true)
                        lastPinch = nil
                        touchDown = ProcessInfo.processInfo.systemUptime // same clock as the motion samples
                        guard !dragging else { return } // grabbed by Double Tap: this touch drops it on release
                        holdTimer = Timer.scheduledTimer(withTimeInterval: holdToDrag, repeats: false) { _ in
                            dragging = true
                            pointer.send(.drag, 1, at: touchDown)
                        }
                    }
                    .onEnded { _ in
                        holdTimer?.invalidate()
                        pressing = false
                        Touch.mark(false)
                        if dragging {
                            dragging = false
                            pointer.send(.drag, 0, at: ProcessInfo.processInfo.systemUptime - 0.05) // just before the lift
                        } else {
                            clicks += 1
                            pointer.send(.leftClick, at: touchDown)
                        }
                    }
            )
            .sensoryFeedback(trigger: dragging) { _, now in .impact(weight: now ? .heavy : .light) }
    }
}

/// How hard the last shake was, against what a finger tap needs: tap and watch it, then pick the sensitivity.
private struct FingerMeter: View {
    let peak: Double
    let level: Int
    let dark: Bool

    var body: some View {
        let need = FingerTapDetector.threshold(level: level).minPeak
        let fill = min(peak / (need * 2), 1)
        VStack(spacing: 3) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(white: dark ? 0.75 : 0.25))
                    Capsule().fill(peak >= need ? Color.orange : Color(white: dark ? 0.4 : 0.6))
                        .frame(width: geo.size.width * fill)
                    Rectangle().fill(dark ? Color.black : Color.white).frame(width: 1.5) // the line to cross
                        .offset(x: geo.size.width / 2)
                }
            }
            .frame(height: 4)
            Text(String(format: "%.2fg", peak))
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(dark ? Color.black : Color(white: 0.5))
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 8)
        .animation(.easeOut(duration: 0.1), value: peak)
    }
}

private struct PadButton: View {
    let symbol: String
    var tint: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(white: 0.16))
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(tint)
                        .contentTransition(.symbolEffect(.replace))
                }
        }
        .buttonStyle(PressStyle())
    }
}

private struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.smooth(duration: 0.12), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in Touch.mark(pressed) } // not a finger tap
    }
}
