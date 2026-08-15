import SwiftUI
import AVFoundation
import Vision

extension Notification.Name {
    /// Posted when opening `tuff://challenge` so the Block tab presents the challenge runner.
    static let tuffOpenChallengeGate = Notification.Name("tuffOpenChallengeGate")
}

// MARK: - Challenge catalogue

enum UnlockChallengeKind: String, CaseIterable, Codable, Identifiable {
    case pushups
    case flashcardQuiz
    case reactionTime
    case aimTrainer
    case mathSprint
    case holdFocus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pushups: return "Pose push‑ups"
        case .flashcardQuiz: return "Flashcard quiz"
        case .reactionTime: return "Reaction burst"
        case .aimTrainer: return "Aim trainer"
        case .mathSprint: return "Mental math sprint"
        case .holdFocus: return "Focus hold"
        }
    }

    var subtitle: String {
        switch self {
        case .pushups:
            return "Camera tracks your elbows — complete 6 full reps facing the lens."
        case .flashcardQuiz:
            return "Answer your own flashcards until you ace 6 in a row."
        case .reactionTime:
            return "Wait for green, then tap as fast as you can — 4 clean hits wins."
        case .aimTrainer:
            return "Hit 6 targets quickly (Human Benchmark‑style)."
        case .mathSprint:
            return "Solve 8 quick arithmetic prompts without mistakes."
        case .holdFocus:
            return "Keep two fingers anchored for 35 seconds."
        }
    }

    /// Persisted preference key.
    static let userDefaultsKey = "tuff_preferredChallengeKind"
}

extension UnlockChallengeKind {
    static func loadSaved() -> UnlockChallengeKind {
        guard let raw = UserDefaults.standard.string(forKey: Self.userDefaultsKey),
              let v = UnlockChallengeKind(rawValue: raw) else { return .pushups }
        return v
    }

    func savePreferred() {
        UserDefaults.standard.set(rawValue, forKey: UnlockChallengeKind.userDefaultsKey)
    }
}

// MARK: - Flashcards

struct UnlockFlashcard: Codable, Identifiable, Equatable {
    var id: UUID
    var front: String
    var back: String

    init(id: UUID = UUID(), front: String, back: String) {
        self.id = id
        self.front = front
        self.back = back
    }
}

enum UnlockFlashcardStore {
    private static let key = "tuff_unlock_flashcards_json"

    static func load() -> [UnlockFlashcard] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let cards = try? JSONDecoder().decode([UnlockFlashcard].self, from: data),
              !cards.isEmpty else {
            return sampleDeck()
        }
        return cards
    }

    static func save(_ cards: [UnlockFlashcard]) {
        if let data = try? JSONEncoder().encode(cards) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func sampleDeck() -> [UnlockFlashcard] {
        [
            UnlockFlashcard(front: "Hydration mantra", back: "One glass before doomscroll"),
            UnlockFlashcard(front: "Breath cadence", back: "4 in · 6 hold · 8 out"),
            UnlockFlashcard(front: "Screen rule", back: "No phone in bed")
        ]
    }
}

// MARK: - Unified challenge presenter

struct ChallengeGateView: View {
    let preferredKind: UnlockChallengeKind
    let unlockMinutes: Int
    var onDismiss: () -> Void
    let onEarnedUnlock: () -> Void

    @EnvironmentObject private var screenTime: ScreenTimeManager
    @State private var chosen: UnlockChallengeKind

    init(
        preferredKind: UnlockChallengeKind,
        unlockMinutes: Int,
        onDismiss: @escaping () -> Void,
        onEarnedUnlock: @escaping () -> Void
    ) {
        self.preferredKind = preferredKind
        self.unlockMinutes = unlockMinutes
        self.onDismiss = onDismiss
        self.onEarnedUnlock = onEarnedUnlock
        _chosen = State(initialValue: preferredKind)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch chosen {
                case .pushups:
                    PushupPoseChallengeView { complete() }
                case .flashcardQuiz:
                    FlashcardQuizChallengeView { complete() }
                case .reactionTime:
                    ReactionBurstChallengeView { complete() }
                case .aimTrainer:
                    AimTrainerChallengeView { complete() }
                case .mathSprint:
                    MathSprintChallengeView { complete() }
                case .holdFocus:
                    HoldFocusChallengeView { complete() }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        onDismiss()
                    }
                    .foregroundColor(TuffColors.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Type", selection: $chosen) {
                            ForEach(UnlockChallengeKind.allCases) { kind in
                                Text(kind.title).tag(kind)
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 18, weight: .medium))
                    }
                    .foregroundColor(TuffColors.accent)
                }
            }
        }
        .onChange(of: chosen) { _, new in new.savePreferred() }
    }

    private func complete() {
        screenTime.grantEarnedUnlock(minutes: unlockMinutes)
        onEarnedUnlock()
    }
}

// MARK: - Push‑ups via Vision pose

private struct PushupPoseChallengeView: View {
    var onFinish: () -> Void

    @StateObject private var session = PoseSession()
    @State private var didFinish = false

    private let targetReps = 6

    var body: some View {
        VStack(spacing: 14) {
            Text("Reach \(targetReps) reps with your elbows bending ≥90°, then locking out.")
                .font(.system(size: 14))
                .foregroundColor(TuffColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            CameraPosePreview(session: session)
                .frame(maxWidth: .infinity)
                .aspectRatio(3 / 4, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.06), lineWidth: 1))
                .padding(.horizontal)

            Text("\(session.repetitions) / \(targetReps) reps")
                .font(.system(size: 32, weight: .black))
                .monospacedDigit()

            if session.cameraDenied {
                Text("Camera permission is needed to track your reps. Enable it under Settings › Tuff.")
                    .font(.system(size: 13))
                    .foregroundColor(.red.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            ProgressView(value: Double(min(session.repetitions, targetReps)), total: Double(targetReps))
                .tint(TuffColors.accent)
                .padding(.horizontal, 32)

            Spacer()
        }
        .padding(.top, 24)
        .navigationTitle("Pose push‑ups")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { session.start() }
        .onDisappear { session.stop() }
        .onChange(of: session.repetitions) { _, new in
            guard !didFinish, new >= targetReps else { return }
            didFinish = true
            onFinish()
        }
    }
}

private final class PoseSession: NSObject, ObservableObject {
    @Published var repetitions = 0
    @Published var cameraDenied = false

    let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "tuff.pose.queue")

    enum PushPhase {
        case needDown
        case needUp
    }

    private var phase: PushPhase = .needDown
    private var lastAngle: CGFloat?

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.configureSession()
                    } else {
                        self.cameraDenied = true
                    }
                }
            }
        default:
            cameraDenied = true
        }
    }

    func stop() {
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
    }

    private func configureSession() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .high
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
            let input = try? AVCaptureDeviceInput(device: device),
            captureSession.canAddInput(input)
        else {
            captureSession.commitConfiguration()
            return
        }
        captureSession.addInput(input)
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }
        captureSession.commitConfiguration()
        DispatchQueue.global(qos: .userInteractive).async { [captureSession] in
            captureSession.startRunning()
        }
    }

    private func processBuffer(_ buffer: CMSampleBuffer) {
        guard let pixel = CMSampleBufferGetImageBuffer(buffer) else { return }
        let request = VNDetectHumanBodyPoseRequest { [weak self] req, _ in
            guard let self else { return }
            guard let obs = req.results?.first as? VNHumanBodyPoseObservation else { return }
            guard let angle = self.primaryElbowAngleDegrees(from: obs) else { return }
            DispatchQueue.main.async {
                self.updateRepState(angle: angle)
            }
        }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixel, orientation: .up, options: [:])
        try? handler.perform([request])
    }

    private func primaryElbowAngleDegrees(from obs: VNHumanBodyPoseObservation) -> CGFloat? {
        func angle(left: Bool) -> CGFloat? {
            let shoulder: VNHumanBodyPoseObservation.JointName = left ? .leftShoulder : .rightShoulder
            let elbow: VNHumanBodyPoseObservation.JointName = left ? .leftElbow : .rightElbow
            let wrist: VNHumanBodyPoseObservation.JointName = left ? .leftWrist : .rightWrist
            guard
                let s = try? obs.recognizedPoint(shoulder), s.confidence > 0.35,
                let e = try? obs.recognizedPoint(elbow), e.confidence > 0.35,
                let w = try? obs.recognizedPoint(wrist), w.confidence > 0.35
            else { return nil }
            return Self.planarAngle(a: CGPoint(x: s.location.x, y: s.location.y),
                                    b: CGPoint(x: e.location.x, y: e.location.y),
                                    c: CGPoint(x: w.location.x, y: w.location.y))
        }
        let l = angle(left: true)
        let r = angle(left: false)
        switch (l, r) {
        case let (lv?, nil): return lv
        case let (nil, rv?): return rv
        case let (lv?, rv?): return lv > rv ? lv : rv
        default: return nil
        }
    }

    private static func planarAngle(a: CGPoint, b: CGPoint, c: CGPoint) -> CGFloat {
        let ab = CGVector(dx: a.x - b.x, dy: a.y - b.y)
        let cb = CGVector(dx: c.x - b.x, dy: c.y - b.y)
        let dot = ab.dx * cb.dx + ab.dy * cb.dy
        let mag = hypot(ab.dx, ab.dy) * hypot(cb.dx, cb.dy)
        guard mag > 0 else { return 180 }
        let cosv = max(-1, min(1, dot / mag))
        return acos(cosv) * 180 / .pi
    }

    private func updateRepState(angle: CGFloat) {
        let smoothed: CGFloat
        if let last = lastAngle {
            smoothed = last * 0.65 + angle * 0.35
        } else {
            smoothed = angle
        }
        lastAngle = smoothed

        switch phase {
        case .needDown:
            if smoothed < 95 { phase = .needUp }
        case .needUp:
            if smoothed > 150 {
                phase = .needDown
                repetitions += 1
            }
        }
    }
}

extension PoseSession: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        processBuffer(sampleBuffer)
    }
}

private struct CameraPosePreview: UIViewRepresentable {
    @ObservedObject var session: PoseSession

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.videoPreviewLayer.session = session.captureSession
        v.videoPreviewLayer.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

// MARK: - Flashcard quiz

private struct FlashcardQuizChallengeView: View {
    var onFinish: () -> Void

    @State private var cards = UnlockFlashcardStore.load()
    @State private var streak = 0
    @State private var current: UnlockFlashcard?
    @State private var answer = ""
    @State private var feedback: String?

    private let target = 6

    var body: some View {
        VStack(spacing: 18) {
            Text("Type the back side exactly (case‑insensitive). \(streak) / \(target) correct.")
                .font(.system(size: 14))
                .foregroundColor(TuffColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if cards.count < 2 {
                Text("Add at least two flashcards from the Block tab before running this challenge.")
                    .foregroundColor(.red.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding()
                Spacer()
            } else if let card = current {
                Text(card.front)
                    .font(.system(size: 22, weight: .bold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                TextField("Your answer", text: $answer)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 32)
                    .onSubmit { check() }

                if let feedback {
                    Text(feedback)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(feedback.contains("Nice") ? TuffColors.accent : .red.opacity(0.85))
                }

                Button("Check answer") { check() }
                    .buttonStyle(.borderedProminent)
                    .tint(TuffColors.accent)

                Spacer()
            } else {
                ProgressView()
                Spacer()
            }
        }
        .padding(.top, 24)
        .navigationTitle("Flashcards")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard cards.count >= 2 else { return }
            pickNext()
        }
    }

    private func pickNext() {
        answer = ""
        feedback = nil
        current = cards.randomElement()
    }

    private func normalized(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func check() {
        guard let card = current else { return }
        guard !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            feedback = "Enter an answer."
            return
        }
        if normalized(answer) == normalized(card.back) {
            streak += 1
            feedback = "Nice!"
            if streak >= target {
                onFinish()
            } else {
                pickNext()
            }
        } else {
            streak = 0
            feedback = "Not quite — streak reset."
        }
    }
}

// MARK: - Reaction burst (Human Benchmark style)

private struct ReactionBurstChallengeView: View {
    var onFinish: () -> Void

    private enum Phase {
        case idle
        case waitingCue
        case readyTap
        case falseStart
    }

    @State private var phase: Phase = .idle
    @State private var hits = 0
    @State private var cueStartedAt: Date?
    @State private var lastReactionMs = 0
    @State private var waitTask: Task<Void, Never>?

    private let needHits = 4

    var body: some View {
        VStack(spacing: 20) {
            Text("Human Benchmark vibes — wait for emerald, tap immediately. Avoid early taps (false starts). Four clean hits clears the shield timer.")
                .font(.system(size: 14))
                .foregroundColor(TuffColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Text("\(hits) / \(needHits)")
                .font(.system(size: 40, weight: .heavy))
                .monospacedDigit()

            if phase == .readyTap, cueStartedAt != nil {
                Text("Last: \(lastReactionMs) ms")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(TuffColors.textSecondary)
            }

            Button(action: arenaTap) {
                RoundedRectangle(cornerRadius: 18)
                    .fill(backgroundColor)
                    .frame(height: 220)
                    .overlay(
                        Text(arenaCaption)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal)

            HStack(spacing: 24) {
                Button("Start drill") {
                    resetAll()
                    startCue()
                }
                Button("Reset") {
                    resetAll()
                }
            }
            .font(.system(size: 15, weight: .semibold))

            Spacer()
        }
        .padding(.top, 12)
        .navigationTitle("Reaction burst")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { waitTask?.cancel() }
    }

    private var backgroundColor: Color {
        switch phase {
        case .readyTap:
            return Color.green.opacity(0.88)
        case .falseStart:
            return Color.red.opacity(0.72)
        default:
            return Color.red.opacity(0.42)
        }
    }

    private var arenaCaption: String {
        switch phase {
        case .idle:
            return "Tap \"Start drill\""
        case .waitingCue:
            return "Wait for green…"
        case .falseStart:
            return "False start!"
        case .readyTap:
            return "Tap now!"
        }
    }

    private func arenaTap() {
        switch phase {
        case .idle:
            break
        case .waitingCue:
            waitTask?.cancel()
            phase = .falseStart
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) {
                if phase == .falseStart {
                    phase = .idle
                }
            }
        case .readyTap:
            guard let cueStartedAt else { return }
            let ms = Int(Date().timeIntervalSince(cueStartedAt) * 1000)
            lastReactionMs = max(0, ms)
            hits += 1
            if hits >= needHits {
                onFinish()
                return
            }
            phase = .idle
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                startCue()
            }
        case .falseStart:
            break
        }
    }

    private func resetAll() {
        waitTask?.cancel()
        waitTask = nil
        hits = 0
        cueStartedAt = nil
        lastReactionMs = 0
        phase = .idle
    }

    private func startCue() {
        guard phase != .waitingCue && phase != .readyTap else { return }
        waitTask?.cancel()
        phase = .waitingCue
        cueStartedAt = nil

        let delay = UInt64(Double.random(in: 0.95 ... 2.95) * 1_000_000_000)
        waitTask = Task {
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard phase == .waitingCue else { return }
                cueStartedAt = Date()
                phase = .readyTap
            }
        }
    }
}

private struct AimTrainerChallengeView: View {
    var onFinish: () -> Void

    @State private var hits = 0
    @State private var target = CGPoint(x: 0.5, y: 0.5)
    @State private var appeared = Date()
    @State private var missTimer: Timer?

    private let arenaSize: CGFloat = 320
    private let needHits = 6
    private let targetDiameter: CGFloat = 52

    var body: some View {
        VStack(spacing: 14) {
            Text("Shoot the orb before it teleports — \(needHits) lock‑ons earns your unlock.")
                .font(.system(size: 14))
                .foregroundColor(TuffColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Text("\(hits) / \(needHits)")
                .font(.system(size: 36, weight: .heavy))

            ZStack {
                Color.black.opacity(0.05)
                    .frame(width: arenaSize, height: arenaSize)
                    .cornerRadius(16)

                Button {
                    registerHit()
                } label: {
                    Circle()
                        .fill(Color.orange.opacity(0.92))
                        .frame(width: targetDiameter, height: targetDiameter)
                }
                .buttonStyle(.plain)
                .position(
                    x: target.x * arenaSize,
                    y: target.y * arenaSize
                )
            }
            .frame(width: arenaSize, height: arenaSize)
            Spacer()
        }
        .padding(.top, 22)
        .navigationTitle("Aim trainer")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            randomizeTarget()
            missTimer?.invalidate()
            missTimer = Timer.scheduledTimer(withTimeInterval: 1.55, repeats: true) { _ in
                if Date().timeIntervalSince(appeared) > 0.35 {
                    randomizeTarget()
                }
            }
        }
        .onDisappear { missTimer?.invalidate() }
    }

    private func randomizeTarget() {
        appeared = Date()
        target = CGPoint(
            x: CGFloat.random(in: 0.14 ... 0.86),
            y: CGFloat.random(in: 0.14 ... 0.86)
        )
    }

    private func registerHit() {
        hits += 1
        if hits >= needHits {
            missTimer?.invalidate()
            onFinish()
        } else {
            randomizeTarget()
        }
    }
}

// MARK: - Math sprint

private struct MathSprintChallengeView: View {
    var onFinish: () -> Void

    @State private var index = 0
    @State private var a = Int.random(in: 3 ... 19)
    @State private var b = Int.random(in: 3 ... 19)
    @State private var op = "+"
    @State private var answer = ""
    @State private var wrong = false

    private let total = 8

    private var prompt: String { "\(a) \(op) \(b)" }
    private var correct: Int {
        switch op {
        case "+": return a + b
        case "-": return a - b
        case "×": return a * b
        default: return a + b
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            Text("Answer \(total) prompts without resetting your streak.")
                .font(.system(size: 14))
                .foregroundColor(TuffColors.textSecondary)

            Text("\(index) / \(total)")
                .font(.system(size: 28, weight: .heavy))

            Text(prompt)
                .font(.system(size: 44, weight: .black))

            TextField("Answer", text: $answer)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 28, weight: .semibold))
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.08)))

            if wrong {
                Text("Incorrect — restarting.")
                    .foregroundColor(.red.opacity(0.85))
                    .font(.system(size: 13, weight: .bold))
            }

            Button("Submit") { submit() }
                .buttonStyle(.borderedProminent)
                .tint(TuffColors.accent)

            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.top, 26)
        .navigationTitle("Math sprint")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { randomize(forceOp: "+") }
    }

    private func randomize(forceOp: String? = nil) {
        a = Int.random(in: 3 ... 21)
        b = Int.random(in: 3 ... 21)
        let ops = ["+", "-", "×"]
        op = forceOp ?? ops.randomElement()!
        if op == "-" {
            // keep non-negative pleasant numbers
            if a < b { swap(&a, &b) }
        }
        answer = ""
        wrong = false
    }

    private func submit() {
        guard let val = Int(answer.trimmingCharacters(in: .whitespaces)) else {
            wrong = true
            return
        }
        if val == correct {
            index += 1
            if index >= total {
                onFinish()
            } else {
                randomize()
            }
        } else {
            wrong = true
            index = 0
            randomize()
        }
    }
}

// MARK: - Hold focus (long press anchored)

private struct HoldFocusChallengeView: View {
    var onFinish: () -> Void

    @State private var isPressing = false
    @State private var progress: CGFloat = 0

    private let seconds: CGFloat = 35

    var body: some View {
        VStack(spacing: 18) {
            Text("Hold your thumb anywhere on the ring without lifting for \(Int(seconds))s.")
                .font(.system(size: 14))
                .foregroundColor(TuffColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            ZStack {
                Circle()
                    .stroke(Color.black.opacity(0.08), lineWidth: 16)
                    .frame(width: 220, height: 220)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(TuffColors.accent, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 220, height: 220)

                Circle()
                    .fill(Color(hex: "F4F4F4"))
                    .frame(width: 160, height: 160)
                    .overlay(Text("Hold").font(.system(size: 26, weight: .bold)))

                Color.clear
                    .frame(width: 220, height: 220)
                    .contentShape(Circle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                if !isPressing { isPressing = true }
                            }
                            .onEnded { _ in
                                isPressing = false
                                progress = 0
                            }
                    )
            }

            Spacer()
        }
        .padding(.top, 24)
        .navigationTitle("Focus hold")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()) { _ in
            guard isPressing else { return }
            progress = min(1, progress + CGFloat(0.05 / seconds))
            if progress >= 1 {
                isPressing = false
                onFinish()
                progress = 0
            }
        }
    }
}

// MARK: - Flashcard editor sheet

struct UnlockFlashcardEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var cards: [UnlockFlashcard] = UnlockFlashcardStore.load()
    @State private var front = ""
    @State private var back = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Add card") {
                    TextField("Front", text: $front)
                    TextField("Back", text: $back)
                    Button("Insert") {
                        let f = front.trimmingCharacters(in: .whitespacesAndNewlines)
                        let b = back.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !f.isEmpty, !b.isEmpty else { return }
                        cards.append(UnlockFlashcard(front: f, back: b))
                        front = ""
                        back = ""
                    }
                }
                Section("Deck") {
                    ForEach(cards) { card in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(card.front).font(.headline)
                            Text(card.back).font(.subheadline).foregroundColor(.secondary)
                        }
                    }
                    .onDelete { cards.remove(atOffsets: $0) }
                }
            }
            .navigationTitle("Flashcards")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        UnlockFlashcardStore.save(cards)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
