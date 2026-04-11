import SwiftUI
import UIKit

struct FriendCarouselEntry: Identifiable, Hashable {
    let id: UUID
    let name: String
    let imageName: String
    let photoURL: String?
    let dailySpentCents: Int
    let isCurrentUser: Bool
}

struct FriendCarouselView: UIViewRepresentable {
    let entries: [FriendCarouselEntry]
    let currentEntryId: UUID?
    var onActiveIndexChanged: ((Int) -> Void)?

    func makeUIView(context: Context) -> WheelView {
        let v = WheelView(entries: entries, currentEntryId: currentEntryId)
        v.onActiveIndexChanged = onActiveIndexChanged
        return v
    }

    func updateUIView(_ uiView: WheelView, context: Context) {
        uiView.onActiveIndexChanged = onActiveIndexChanged
        uiView.updateIfNeeded(entries: entries, currentEntryId: currentEntryId)
    }
}

final class WheelView: UIView {

    // MARK: Geometry (mirrors HTML constants)

    private let rOuter: CGFloat = 870
    private let rInner: CGFloat = 806
    private var rMid: CGFloat { (rOuter + rInner) / 2 }
    private let slotW: CGFloat = 74
    private let arc: CGFloat = 0.28
    private var vcx: CGFloat { bounds.width / 2 }
    private var vcy: CGFloat { 90 + rMid }

    // MARK: Data

    private var entries: [FriendCarouselEntry]
    private var currentEntryId: UUID?
    var onActiveIndexChanged: ((Int) -> Void)?

    private var n: Int { entries.count }
    private var hardMax: CGFloat { CGFloat(max(n - 1, 0)) * slotW }

    // MARK: Physics

    private var stripPos: CGFloat = 0
    private var velPx: CGFloat = 0
    private enum PhysState { case idle, dragging, momentum, snap, spring, intro }
    private var phState: PhysState = .idle
    private var snapTarget: CGFloat = 0

    // MARK: Drag

    private var lastDragX: CGFloat = 0
    private var lastDragT: Double = 0
    private var dragStartT: Double = 0
    private var dragStartX: CGFloat = 0
    private var dragStartY: CGFloat = 0
    private var dragDistance: CGFloat = 0
    private struct VSample { var dx: CGFloat; var dt: Double }
    private var velSamples: [VSample] = []

    // MARK: Display links

    private var physLink: CADisplayLink?
    private var introLink: CADisplayLink?
    private var lastPhysT: CFTimeInterval = 0
    private var introStart: CFTimeInterval = 0
    private var introFrom: CGFloat = 0
    private var introTo: CGFloat = 0
    private let introDur: CFTimeInterval = 2.1

    // MARK: Avatar image cache

    private var avatarImages: [UUID: UIImage] = [:]
    private var lastPanelIdx: Int = -1

    private static let remoteCache = NSCache<NSString, UIImage>()
    private static var inFlightURLs = Set<String>()
    private static let inFlightLock = NSLock()

    private static let fallbackColors = [
        "2e7d32", "6d4c8e", "c0392b", "2980b9", "8e44ad", "e67e22",
        "2D7A4F", "16a085", "d35400", "1a6fa6", "b71c1c", "0277bd",
        "4a148c", "e65100", "004d40", "880e4f", "1565c0", "33691e",
    ]

    // MARK: Init

    init(entries: [FriendCarouselEntry], currentEntryId: UUID?) {
        self.entries = entries
        self.currentEntryId = currentEntryId
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        alignToCurrentEntry()
        loadImages()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        physLink?.invalidate()
        introLink?.invalidate()
    }

    func updateIfNeeded(entries: [FriendCarouselEntry], currentEntryId: UUID?) {
        if self.entries == entries, self.currentEntryId == currentEntryId { return }
        update(entries: entries, currentEntryId: currentEntryId)
    }

    private func update(entries: [FriendCarouselEntry], currentEntryId: UUID?) {
        let previousId: UUID? = {
            guard n > 0 else { return nil }
            return self.entries[activeIdx()].id
        }()

        self.entries = entries
        self.currentEntryId = currentEntryId
        loadImages()

        guard n > 0 else {
            stripPos = 0
            velPx = 0
            phState = .idle
            setNeedsDisplay()
            return
        }

        if let previousId,
           let idx = self.entries.firstIndex(where: { $0.id == previousId }) {
            stripPos = CGFloat(idx) * slotW
        } else {
            alignToCurrentEntry()
        }

        stripPos = clamp(stripPos, 0, hardMax)
        setNeedsDisplay()
        notifyPanel()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, n > 1 else { return }
        let idx = entries.firstIndex(where: { $0.id == currentEntryId }) ?? 0
        introFrom = hardMax * 0.28
        introTo = CGFloat(idx) * slotW
        stripPos = introFrom
        phState = .intro
        introStart = CACurrentMediaTime()
        introLink?.invalidate()
        introLink = CADisplayLink(target: self, selector: #selector(introStep))
        introLink?.add(to: .main, forMode: .common)
    }

    // MARK: Images

    private func loadImages() {
        var nextMap: [UUID: UIImage] = [:]

        for entry in entries {
            if let existing = avatarImages[entry.id] {
                nextMap[entry.id] = existing
                continue
            }

            if !entry.imageName.isEmpty, let local = UIImage(named: entry.imageName) {
                nextMap[entry.id] = local
                continue
            }

            guard let urlString = entry.photoURL, !urlString.isEmpty else { continue }
            if let cached = Self.remoteCache.object(forKey: urlString as NSString) {
                nextMap[entry.id] = cached
                continue
            }
            loadRemoteImage(urlString: urlString, entryId: entry.id)
        }

        avatarImages = nextMap
    }

    private func loadRemoteImage(urlString: String, entryId: UUID) {
        guard let url = URL(string: urlString) else { return }

        Self.inFlightLock.lock()
        if Self.inFlightURLs.contains(urlString) {
            Self.inFlightLock.unlock()
            return
        }
        Self.inFlightURLs.insert(urlString)
        Self.inFlightLock.unlock()

        URLSession.shared.dataTask(with: url) { data, _, _ in
            defer {
                Self.inFlightLock.lock()
                Self.inFlightURLs.remove(urlString)
                Self.inFlightLock.unlock()
            }

            guard let data, let image = UIImage(data: data) else { return }
            let targetSize = CGSize(width: 80, height: 80)
            let renderer = UIGraphicsImageRenderer(size: targetSize)
            let prepared = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: targetSize))
            }
            Self.remoteCache.setObject(prepared, forKey: urlString as NSString)

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.entries.contains(where: { $0.id == entryId }) else { return }
                self.avatarImages[entryId] = prepared
                self.setNeedsDisplay()
            }
        }.resume()
    }

    // MARK: Intro

    @objc private func introStep() {
        let t = CGFloat(min((CACurrentMediaTime() - introStart) / introDur, 1))
        let eased = 1 - pow(1 - t, 4)
        stripPos = introFrom + (introTo - introFrom) * eased
        setNeedsDisplay()
        notifyPanel()
        if t >= 1 {
            stripPos = introTo
            phState = .idle
            introLink?.invalidate()
            introLink = nil
            setNeedsDisplay()
            notifyPanel()
        }
    }

    // MARK: Physics loop

    private func startPhysLink() {
        physLink?.invalidate()
        lastPhysT = CACurrentMediaTime()
        physLink = CADisplayLink(target: self, selector: #selector(physStep))
        physLink?.add(to: .main, forMode: .common)
    }

    private func stopPhysLink() {
        physLink?.invalidate()
        physLink = nil
    }

    @objc private func physStep() {
        guard let link = physLink else { return }
        let now = link.timestamp
        let dt = CGFloat(min((now - lastPhysT) * 1000, 32))
        lastPhysT = now

        switch phState {
        case .momentum:
            stripPos += velPx * dt
            velPx *= pow(0.982, dt)
            let over = stripPos - clamp(stripPos, 0, hardMax)
            if over != 0 { velPx -= over * 0.018 * dt }
            if abs(velPx) < 0.04, stripPos >= 0, stripPos <= hardMax {
                phState = .snap
                snapTarget = clamp(round(stripPos / slotW) * slotW, 0, hardMax)
            }

        case .spring:
            let bounded = clamp(stripPos, 0, hardMax)
            snapTarget = clamp(round(bounded / slotW) * slotW, 0, hardMax)
            let diff = snapTarget - stripPos
            velPx += diff * 0.22 * (dt / 16)
            velPx *= 0.75
            stripPos += velPx * (dt / 16)
            if abs(diff) < 0.4, abs(velPx) < 0.01 {
                stripPos = snapTarget
                phState = .idle
                stopPhysLink()
            }

        case .snap:
            let diff = snapTarget - stripPos
            stripPos += diff * 0.22 * (dt / 16)
            if abs(diff) < 0.25 {
                stripPos = snapTarget
                phState = .idle
                stopPhysLink()
            }

        default:
            stopPhysLink()
            return
        }

        setNeedsDisplay()
        notifyPanel()
    }

    // MARK: Helpers

    private func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        max(lo, min(hi, v))
    }

    private func rubberBand(_ x: CGFloat) -> CGFloat {
        let bounce = slotW * 3
        if x < 0 {
            let over = -x
            return -(over * pow(0.45, over / bounce))
        }
        if x > hardMax {
            let over = x - hardMax
            return hardMax + over * pow(0.45, over / bounce)
        }
        return x
    }

    private func activeIdx() -> Int {
        guard n > 0 else { return 0 }
        return Int(clamp(round(stripPos / slotW), 0, CGFloat(n - 1)))
    }

    private func alignToCurrentEntry() {
        guard n > 0 else {
            stripPos = 0
            return
        }
        let idx = entries.firstIndex(where: { $0.id == currentEntryId }) ?? 0
        stripPos = CGFloat(idx) * slotW
    }

    private func notifyPanel() {
        guard n > 0 else { return }
        let idx = activeIdx()
        guard idx != lastPanelIdx else { return }
        lastPanelIdx = idx
        onActiveIndexChanged?(idx)
    }

    private func initials(from name: String) -> String {
        name.split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
            .map(String.init)
            .joined()
            .uppercased()
    }

    // MARK: Touch

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard n > 1, phState != .intro else { return }
        stopPhysLink()
        phState = .dragging
        guard let t = touches.first else { return }
        lastDragX = t.location(in: self).x
        lastDragT = t.timestamp * 1000
        dragStartT = t.timestamp * 1000
        dragStartX = t.location(in: self).x
        dragStartY = t.location(in: self).y
        dragDistance = 0
        velSamples.removeAll()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard phState == .dragging, n > 1 else { return }
        guard let t = touches.first else { return }
        let x = t.location(in: self).x
        let y = t.location(in: self).y
        let ts = t.timestamp * 1000
        let dx = x - lastDragX
        let dt = max(ts - lastDragT, 1)
        dragDistance = max(dragDistance, hypot(x - dragStartX, y - dragStartY))
        velSamples.append(VSample(dx: dx, dt: dt))
        if velSamples.count > 6 { velSamples.removeFirst() }
        stripPos = rubberBand(stripPos + dx)
        lastDragX = x
        lastDragT = ts
        setNeedsDisplay()
        notifyPanel()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard phState == .dragging else { return }

        if let t = touches.first {
            let tapDuration = (t.timestamp * 1000) - dragStartT
            if dragDistance < 8, tapDuration < 250 {
                let tapX = t.location(in: self).x
                let projected = Int(round((stripPos - (tapX - vcx)) / slotW))
                snapTarget = clamp(CGFloat(projected) * slotW, 0, hardMax)
                phState = .snap
                startPhysLink()
                return
            }
        }

        var totalDx: CGFloat = 0
        var totalDt: Double = 0
        velSamples.forEach {
            totalDx += $0.dx
            totalDt += $0.dt
        }
        velPx = clamp(totalDt > 0 ? totalDx / CGFloat(totalDt) : 0, -4.5, 4.5)
        if stripPos < 0 || stripPos > hardMax {
            phState = .spring
        } else if abs(velPx) > 0.05 {
            phState = .momentum
        } else {
            phState = .snap
            snapTarget = clamp(round(stripPos / slotW) * slotW, 0, hardMax)
        }
        startPhysLink()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }

    // MARK: Drawing

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), n > 0 else { return }
        let cx = vcx
        let cy = vcy

        func ca(_ a: CGFloat) -> CGFloat { a - .pi / 2 }
        func sa(_ i: Int) -> CGFloat { (stripPos - CGFloat(i) * slotW) / rMid }
        func pt(_ a: CGFloat, _ r: CGFloat) -> CGPoint {
            CGPoint(x: cx + r * sin(a), y: cy - r * cos(a))
        }

        let c0 = ca(-arc - 0.04)
        let c1 = ca(arc + 0.04)

        // Background arc
        ctx.saveGState()
        ctx.beginPath()
        ctx.addArc(center: CGPoint(x: cx, y: cy), radius: rOuter, startAngle: c0, endAngle: c1, clockwise: false)
        ctx.addArc(center: CGPoint(x: cx, y: cy), radius: rInner, startAngle: c1, endAngle: c0, clockwise: true)
        ctx.closePath()
        ctx.setFillColor(UIColor(red: 0.067, green: 0.067, blue: 0.067, alpha: 1).cgColor)
        ctx.fillPath()

        // Clip to arc band
        ctx.beginPath()
        ctx.addArc(center: CGPoint(x: cx, y: cy), radius: rOuter, startAngle: c0, endAngle: c1, clockwise: false)
        ctx.addArc(center: CGPoint(x: cx, y: cy), radius: rInner, startAngle: c1, endAngle: c0, clockwise: true)
        ctx.closePath()
        ctx.clip()

        // Alternating slot fills
        for i in 0..<n {
            let a = sa(i)
            let hw = slotW / (2 * rMid)
            guard a > -arc - hw * 2, a < arc + hw * 2 else { continue }
            let col: UIColor = i % 2 == 0 ? UIColor(white: 0.102, alpha: 1) : UIColor(white: 0.91, alpha: 1)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: cx, y: cy))
            ctx.addArc(center: CGPoint(x: cx, y: cy), radius: rOuter + 10,
                       startAngle: ca(a - hw), endAngle: ca(a + hw), clockwise: false)
            ctx.closePath()
            ctx.setFillColor(col.cgColor)
            ctx.fillPath()
        }

        // Punch out inner hole
        ctx.setBlendMode(.destinationOut)
        ctx.beginPath()
        ctx.addArc(center: CGPoint(x: cx, y: cy), radius: rInner - 1, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.fillPath()
        ctx.setBlendMode(.normal)

        // Divider lines
        for i in 0...n {
            let divA = (stripPos - (CGFloat(i) - 0.5) * slotW) / rMid
            guard divA > -arc - 0.05, divA < arc + 0.05 else { continue }
            ctx.beginPath()
            ctx.move(to: pt(divA, rInner))
            ctx.addLine(to: pt(divA, rOuter))
            ctx.setStrokeColor(UIColor(white: 0.31, alpha: 0.4).cgColor)
            ctx.setLineWidth(1)
            ctx.strokePath()
        }

        ctx.restoreGState()

        // Avatars
        let avR: CGFloat = 20
        for i in 0..<n {
            let a = sa(i)
            let hw = slotW / (2 * rMid)
            guard a > -arc - hw, a < arc + hw else { continue }
            let p = pt(a, rMid)
            let isActive = abs(a) < hw
            let entry = entries[i]

            if isActive {
                ctx.saveGState()
                ctx.translateBy(x: p.x, y: p.y)
                ctx.rotate(by: a)
                ctx.beginPath()
                ctx.addArc(center: .zero, radius: avR + 7, startAngle: 0, endAngle: .pi * 2, clockwise: false)
                ctx.setFillColor(UIColor(hex: "2D7A4F").withAlphaComponent(0.22).cgColor)
                ctx.fillPath()
                ctx.restoreGState()
            }

            ctx.saveGState()
            ctx.translateBy(x: p.x, y: p.y)
            ctx.rotate(by: a)
            ctx.beginPath()
            ctx.addArc(center: .zero, radius: avR, startAngle: 0, endAngle: .pi * 2, clockwise: false)
            ctx.clip()

            if let img = avatarImages[entry.id] {
                img.draw(in: CGRect(x: -avR, y: -avR, width: avR * 2, height: avR * 2))
            } else {
                let hex = Self.fallbackColors[i % Self.fallbackColors.count]
                UIColor(hex: hex).setFill()
                ctx.fill(CGRect(x: -avR, y: -avR, width: avR * 2, height: avR * 2))
                let str = NSAttributedString(string: initials(from: entry.name), attributes: [
                    .font: UIFont.systemFont(ofSize: 11, weight: .bold),
                    .foregroundColor: UIColor.white,
                ])
                let sz = str.size()
                str.draw(at: CGPoint(x: -sz.width / 2, y: -sz.height / 2))
            }
            ctx.restoreGState()

            ctx.saveGState()
            ctx.translateBy(x: p.x, y: p.y)
            ctx.rotate(by: a)
            ctx.beginPath()
            ctx.addArc(center: .zero, radius: avR, startAngle: 0, endAngle: .pi * 2, clockwise: false)
            ctx.setStrokeColor(isActive ? UIColor(hex: "2D7A4F").cgColor : UIColor(white: 1, alpha: 0.15).cgColor)
            ctx.setLineWidth(isActive ? 2.5 : 1.2)
            ctx.strokePath()
            ctx.restoreGState()
        }

        // Top-3 markers: larger, flat, above tiles
        for i in 0..<min(n, 3) {
            let a = sa(i)
            let hw = slotW / (2 * rMid)
            guard a > -arc - hw, a < arc + hw else { continue }

            let base = pt(a, rMid)
            let markerCenter = CGPoint(x: base.x, y: base.y - avR - 46)
            let now = CGFloat(CACurrentMediaTime())
            let proximity = max(0, 1 - abs(a) / (hw * 2.6))
            let pulse = i == 0 ? (1 + 0.18 * proximity * (0.5 + 0.5 * sin(now * 10))) : 1

            switch i {
            case 0:
                let path = UIBezierPath()
                let points = 5
                let outer: CGFloat = 13.5 * pulse
                let inner: CGFloat = 6.1 * pulse
                for idx in 0..<(points * 2) {
                    let angle = CGFloat(idx) * .pi / CGFloat(points) - .pi / 2
                    let radius = idx % 2 == 0 ? outer : inner
                    let p = CGPoint(
                        x: markerCenter.x + cos(angle) * radius,
                        y: markerCenter.y + sin(angle) * radius
                    )
                    if idx == 0 { path.move(to: p) } else { path.addLine(to: p) }
                }
                path.close()
                ctx.addPath(path.cgPath)
                ctx.setFillColor(UIColor(hex: "FFC83D").cgColor)
                ctx.fillPath()
                ctx.addPath(path.cgPath)
                ctx.setStrokeColor(UIColor(hex: "2D7A4F").cgColor)
                ctx.setLineWidth(2.0)
                ctx.strokePath()

            case 1:
                let h: CGFloat = 12.5
                let w: CGFloat = 10.5
                let diamond = UIBezierPath()
                diamond.move(to: CGPoint(x: markerCenter.x, y: markerCenter.y - h))
                diamond.addLine(to: CGPoint(x: markerCenter.x + w, y: markerCenter.y))
                diamond.addLine(to: CGPoint(x: markerCenter.x, y: markerCenter.y + h))
                diamond.addLine(to: CGPoint(x: markerCenter.x - w, y: markerCenter.y))
                diamond.close()
                ctx.addPath(diamond.cgPath)
                ctx.setFillColor(UIColor(hex: "D6DDE8").cgColor)
                ctx.fillPath()
                ctx.addPath(diamond.cgPath)
                ctx.setStrokeColor(UIColor(hex: "2D7A4F").cgColor)
                ctx.setLineWidth(2.0)
                ctx.strokePath()

            default:
                let halfW: CGFloat = 12
                let topY: CGFloat = 9
                let tipY: CGFloat = 13
                let tri = UIBezierPath()
                tri.move(to: CGPoint(x: markerCenter.x - halfW, y: markerCenter.y - topY))
                tri.addLine(to: CGPoint(x: markerCenter.x + halfW, y: markerCenter.y - topY))
                tri.addLine(to: CGPoint(x: markerCenter.x, y: markerCenter.y + tipY))
                tri.close()
                ctx.addPath(tri.cgPath)
                ctx.setFillColor(UIColor(hex: "CD7F32").cgColor)
                ctx.fillPath()
                ctx.addPath(tri.cgPath)
                ctx.setStrokeColor(UIColor(hex: "2D7A4F").cgColor)
                ctx.setLineWidth(2.0)
                ctx.strokePath()

            }
        }

        // Outer + inner borders
        ctx.saveGState()
        ctx.setStrokeColor(UIColor(white: 0.165, alpha: 1).cgColor)
        ctx.setLineWidth(1.5)
        for r in [rOuter, rInner] {
            ctx.beginPath()
            ctx.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: c0, endAngle: c1, clockwise: false)
            ctx.strokePath()
        }

        // Active slot highlight arcs
        let ahw = slotW / (2 * rMid) + 0.001
        ctx.setStrokeColor(UIColor(hex: "2D7A4F").cgColor)
        ctx.setLineWidth(3)
        ctx.beginPath()
        ctx.addArc(center: CGPoint(x: cx, y: cy), radius: rOuter + 2, startAngle: ca(-ahw), endAngle: ca(ahw), clockwise: false)
        ctx.strokePath()
        ctx.beginPath()
        ctx.addArc(center: CGPoint(x: cx, y: cy), radius: rInner - 2, startAngle: ca(-ahw), endAngle: ca(ahw), clockwise: false)
        ctx.strokePath()
        ctx.restoreGState()
    }
}

private extension UIColor {
    convenience init(hex: String) {
        let h = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        self.init(
            red: CGFloat((int >> 16) & 0xFF) / 255,
            green: CGFloat((int >> 8) & 0xFF) / 255,
            blue: CGFloat(int & 0xFF) / 255,
            alpha: 1
        )
    }
}
