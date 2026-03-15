import SwiftUI
import UIKit

// MARK: - SwiftUI wrapper

struct FriendCarouselView: UIViewRepresentable {
    let users: [TuffUser]
    let currentUserId: UUID
    var onActiveIndexChanged: ((Int) -> Void)?

    func makeUIView(context: Context) -> WheelView {
        let v = WheelView(users: users, currentUserId: currentUserId)
        v.onActiveIndexChanged = onActiveIndexChanged
        return v
    }

    func updateUIView(_ uiView: WheelView, context: Context) {}
}

// MARK: - WheelView

final class WheelView: UIView {

    // ── Geometry (mirrors HTML constants exactly) ──────────────────────────
    private let rOuter: CGFloat = 870
    private let rInner: CGFloat = 806
    private var rMid:   CGFloat { (rOuter + rInner) / 2 }   // 838
    private let slotW:  CGFloat = 74
    private let arc:    CGFloat = 0.28
    private var vcx: CGFloat { bounds.width / 2 }
    private var vcy: CGFloat { 82 + rMid }                  // 920

    // ── Data ───────────────────────────────────────────────────────────────
    let users: [TuffUser]
    let currentUserId: UUID
    var onActiveIndexChanged: ((Int) -> Void)?

    private var n: Int { users.count }
    private var hardMax: CGFloat { CGFloat(max(n - 1, 0)) * slotW }

    // ── Physics state (velPx = pixels / ms, matching HTML) ─────────────────
    private var stripPos:   CGFloat = 0
    private var velPx:      CGFloat = 0
    private enum PhysState { case idle, dragging, momentum, snap, spring, intro }
    private var phState:    PhysState = .idle
    private var snapTarget: CGFloat = 0

    // ── Drag tracking ──────────────────────────────────────────────────────
    private var lastDragX: CGFloat = 0
    private var lastDragT: Double  = 0   // ms
    private struct VSample { var dx: CGFloat; var dt: Double }
    private var velSamples: [VSample] = []

    // ── Display links ──────────────────────────────────────────────────────
    private var physLink:  CADisplayLink?
    private var introLink: CADisplayLink?
    private var lastPhysT: CFTimeInterval = 0
    private var introStart: CFTimeInterval = 0
    private var introFrom:  CGFloat = 0
    private var introTo:    CGFloat = 0
    private let introDur:   CFTimeInterval = 2.1

    // ── Avatar images ──────────────────────────────────────────────────────
    private var avatarImages: [UUID: UIImage] = [:]

    private var lastPanelIdx: Int = -1

    private static let fallbackColors = [
        "2e7d32","6d4c8e","c0392b","2980b9","8e44ad","e67e22",
        "2D7A4F","16a085","d35400","1a6fa6","b71c1c","0277bd",
        "4a148c","e65100","004d40","880e4f","1565c0","33691e",
    ]

    // MARK: init

    init(users: [TuffUser], currentUserId: UUID) {
        self.users = users
        self.currentUserId = currentUserId
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        loadImages()
        let youIdx = users.firstIndex(where: { $0.id == currentUserId }) ?? 0
        stripPos = CGFloat(youIdx) * slotW
    }
    required init?(coder: NSCoder) { fatalError() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        let youIdx = users.firstIndex(where: { $0.id == currentUserId }) ?? 0
        introFrom = hardMax * 0.28
        introTo   = CGFloat(youIdx) * slotW
        stripPos  = introFrom
        phState   = .intro
        introStart = CACurrentMediaTime()
        introLink?.invalidate()
        introLink = CADisplayLink(target: self, selector: #selector(introStep))
        introLink?.add(to: .main, forMode: .common)
    }

    // MARK: Image loading

    private func loadImages() {
        for user in users {
            if let img = UIImage(named: user.imageName) {
                avatarImages[user.id] = img
            }
        }
    }

    // MARK: Intro animation

    @objc private func introStep() {
        let t = CGFloat(min((CACurrentMediaTime() - introStart) / introDur, 1))
        let eased = 1 - pow(1 - t, 4)
        stripPos = introFrom + (introTo - introFrom) * eased
        setNeedsDisplay(); notifyPanel()
        if t >= 1 {
            stripPos = introTo; phState = .idle
            introLink?.invalidate(); introLink = nil
            setNeedsDisplay(); notifyPanel()
        }
    }

    // MARK: Physics loop

    private func startPhysLink() {
        physLink?.invalidate()
        lastPhysT = CACurrentMediaTime()
        physLink = CADisplayLink(target: self, selector: #selector(physStep))
        physLink?.add(to: .main, forMode: .common)
    }
    private func stopPhysLink() { physLink?.invalidate(); physLink = nil }

    @objc private func physStep() {
        guard let link = physLink else { return }
        let now = link.timestamp
        let dt  = CGFloat(min((now - lastPhysT) * 1000, 32))   // ms
        lastPhysT = now

        switch phState {
        case .momentum:
            stripPos += velPx * dt
            velPx    *= pow(0.982, dt)
            let over  = stripPos - clamp(stripPos, 0, hardMax)
            if over != 0 { velPx -= over * 0.018 * dt }
            if abs(velPx) < 0.04 && stripPos >= 0 && stripPos <= hardMax {
                phState    = .snap
                snapTarget = clamp(round(stripPos / slotW) * slotW, 0, hardMax)
            }
        case .spring:
            let bound  = clamp(stripPos, 0, hardMax)
            snapTarget = clamp(round(bound / slotW) * slotW, 0, hardMax)
            let diff   = snapTarget - stripPos
            velPx     += diff * 0.22 * (dt / 16)
            velPx     *= 0.75
            stripPos  += velPx * (dt / 16)
            if abs(diff) < 0.4 && abs(velPx) < 0.01 {
                stripPos = snapTarget; phState = .idle; stopPhysLink()
            }
        case .snap:
            let diff  = snapTarget - stripPos
            stripPos += diff * 0.22 * (dt / 16)
            if abs(diff) < 0.25 { stripPos = snapTarget; phState = .idle; stopPhysLink() }
        default:
            stopPhysLink(); return
        }
        setNeedsDisplay(); notifyPanel()
    }

    // MARK: Helpers

    private func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        max(lo, min(hi, v))
    }

    private func rubberBand(_ x: CGFloat) -> CGFloat {
        let bounce = slotW * 3
        if x < 0       { let o = -x;        return -(o * pow(0.45, o / bounce)) }
        if x > hardMax { let o = x - hardMax; return hardMax + o * pow(0.45, o / bounce) }
        return x
    }

    private func activeIdx() -> Int {
        Int(clamp(round(stripPos / slotW), 0, CGFloat(n - 1)))
    }

    private func notifyPanel() {
        let idx = activeIdx()
        guard idx != lastPanelIdx else { return }
        lastPanelIdx = idx
        DispatchQueue.main.async { [weak self] in self?.onActiveIndexChanged?(idx) }
    }

    // MARK: Touch

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard phState != .intro else { return }
        stopPhysLink()
        phState = .dragging
        let t = touches.first!
        lastDragX = t.location(in: self).x
        lastDragT = t.timestamp * 1000
        velSamples.removeAll()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard phState == .dragging else { return }
        let t  = touches.first!
        let x  = t.location(in: self).x
        let ts = t.timestamp * 1000
        let dx = x - lastDragX
        let dt = max(ts - lastDragT, 1)
        velSamples.append(VSample(dx: dx, dt: dt))
        if velSamples.count > 6 { velSamples.removeFirst() }
        stripPos  = rubberBand(stripPos + dx)
        lastDragX = x; lastDragT = ts
        setNeedsDisplay(); notifyPanel()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard phState == .dragging else { return }
        var tDx: CGFloat = 0; var tDt: Double = 0
        velSamples.forEach { tDx += $0.dx; tDt += $0.dt }
        velPx = clamp(tDt > 0 ? tDx / CGFloat(tDt) : 0, -4.5, 4.5)
        if stripPos < 0 || stripPos > hardMax {
            phState = .spring
        } else if abs(velPx) > 0.05 {
            phState = .momentum
        } else {
            phState    = .snap
            snapTarget = clamp(round(stripPos / slotW) * slotW, 0, hardMax)
        }
        startPhysLink()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: nil)
    }

    // MARK: Drawing

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), n > 0 else { return }
        let cx = vcx, cy = vcy

        // Helpers
        func ca(_ a: CGFloat) -> CGFloat { a - .pi / 2 }
        func sa(_ i: Int) -> CGFloat { (stripPos - CGFloat(i) * slotW) / rMid }
        func pt(_ a: CGFloat, _ r: CGFloat) -> CGPoint {
            CGPoint(x: cx + r * sin(a), y: cy - r * cos(a))
        }

        let c0 = ca(-arc - 0.04), c1 = ca(arc + 0.04)

        // ── Background arc fill ────────────────────────────────────────────
        ctx.saveGState()
        ctx.beginPath()
        ctx.addArc(center: CGPoint(x:cx,y:cy), radius:rOuter, startAngle:c0, endAngle:c1, clockwise:false)
        ctx.addArc(center: CGPoint(x:cx,y:cy), radius:rInner, startAngle:c1, endAngle:c0, clockwise:true)
        ctx.closePath()
        ctx.setFillColor(UIColor(red:0.067,green:0.067,blue:0.067,alpha:1).cgColor)
        ctx.fillPath()

        // ── Clip to arc band ───────────────────────────────────────────────
        ctx.beginPath()
        ctx.addArc(center: CGPoint(x:cx,y:cy), radius:rOuter, startAngle:c0, endAngle:c1, clockwise:false)
        ctx.addArc(center: CGPoint(x:cx,y:cy), radius:rInner, startAngle:c1, endAngle:c0, clockwise:true)
        ctx.closePath()
        ctx.clip()

        // ── Alternating slot fills ─────────────────────────────────────────
        for i in 0..<n {
            let a = sa(i), hw = slotW / (2 * rMid)
            guard a > -arc - hw*2 && a < arc + hw*2 else { continue }
            let col: UIColor = i % 2 == 0
                ? UIColor(white:0.102, alpha:1)
                : UIColor(white:0.91,  alpha:1)
            ctx.beginPath()
            ctx.move(to: CGPoint(x:cx,y:cy))
            ctx.addArc(center:CGPoint(x:cx,y:cy), radius:rOuter+10,
                       startAngle:ca(a-hw), endAngle:ca(a+hw), clockwise:false)
            ctx.closePath()
            ctx.setFillColor(col.cgColor); ctx.fillPath()
        }

        // ── Punch out inner hole ───────────────────────────────────────────
        ctx.setBlendMode(.destinationOut)
        ctx.beginPath()
        ctx.addArc(center:CGPoint(x:cx,y:cy), radius:rInner-1, startAngle:0, endAngle:.pi*2, clockwise:false)
        ctx.fillPath()
        ctx.setBlendMode(.normal)

        // ── Medal bands: gold / silver / bronze for rank 0/1/2 ─────────────
        let medals: [(Int, String, String, String)] = [
            (0, "C8960C", "FFE566", "7A5200"),
            (1, "A0A0A8", "FFFFFF", "505055"),
            (2, "A0522D", "F4A460", "4A1C00"),
        ]
        let sO = rOuter - 1, sI = rOuter - 10
        for (i, base, hi, sh) in medals {
            guard i < n else { continue }
            let a = sa(i), hw = slotW / (2 * rMid)
            guard a > -arc - hw && a < arc + hw else { continue }
            let sA = a - hw + 0.003, eA = a + hw - 0.003
            func band(_ r1: CGFloat, _ r2: CGFloat, _ hex: String, _ alpha: CGFloat) {
                ctx.beginPath()
                ctx.addArc(center:CGPoint(x:cx,y:cy), radius:r1, startAngle:ca(sA), endAngle:ca(eA), clockwise:false)
                ctx.addArc(center:CGPoint(x:cx,y:cy), radius:r2, startAngle:ca(eA), endAngle:ca(sA), clockwise:true)
                ctx.closePath()
                ctx.setFillColor(UIColor(hex:hex).withAlphaComponent(alpha).cgColor)
                ctx.fillPath()
            }
            band(sO, sI,   base, 1.0)
            band(sO, sO-3, hi,   0.6)
            band(sI+3, sI, sh,   0.4)
        }

        // ── Divider lines ──────────────────────────────────────────────────
        for i in 0...n {
            let divA = (stripPos - (CGFloat(i) - 0.5) * slotW) / rMid
            guard divA > -arc - 0.05 && divA < arc + 0.05 else { continue }
            ctx.beginPath()
            ctx.move(to: pt(divA, rInner)); ctx.addLine(to: pt(divA, rOuter))
            ctx.setStrokeColor(UIColor(white:0.31, alpha:0.4).cgColor)
            ctx.setLineWidth(1); ctx.strokePath()
        }

        ctx.restoreGState()

        // ── Avatars (drawn outside the arc clip) ───────────────────────────
        let avR: CGFloat = 20
        for i in 0..<n {
            let a = sa(i), hw = slotW / (2 * rMid)
            guard a > -arc - hw && a < arc + hw else { continue }
            let p = pt(a, rMid)
            let isActive = abs(a) < hw
            let user = users[i]

            // Active glow
            if isActive {
                ctx.saveGState()
                ctx.translateBy(x:p.x, y:p.y); ctx.rotate(by:a)
                ctx.beginPath()
                ctx.addArc(center:.zero, radius:avR+7, startAngle:0, endAngle:.pi*2, clockwise:false)
                ctx.setFillColor(UIColor(hex:"2D7A4F").withAlphaComponent(0.22).cgColor)
                ctx.fillPath()
                ctx.restoreGState()
            }

            // Avatar circle (clipped)
            ctx.saveGState()
            ctx.translateBy(x:p.x, y:p.y); ctx.rotate(by:a)
            ctx.beginPath()
            ctx.addArc(center:.zero, radius:avR, startAngle:0, endAngle:.pi*2, clockwise:false)
            ctx.clip()

            if let img = avatarImages[user.id] {
                img.draw(in: CGRect(x:-avR, y:-avR, width:avR*2, height:avR*2))
            } else {
                let hex = Self.fallbackColors[i % Self.fallbackColors.count]
                UIColor(hex: hex).setFill()
                ctx.fill(CGRect(x:-avR, y:-avR, width:avR*2, height:avR*2))
                let initials = user.name.split(separator:" ").prefix(2)
                    .compactMap{ $0.first }.map{ String($0) }.joined()
                let str = NSAttributedString(string: initials, attributes: [
                    .font: UIFont.systemFont(ofSize: 11, weight: .bold),
                    .foregroundColor: UIColor.white,
                ])
                let sz = str.size()
                str.draw(at: CGPoint(x: -sz.width/2, y: -sz.height/2))
            }
            ctx.restoreGState()

            // Ring
            ctx.saveGState()
            ctx.translateBy(x:p.x, y:p.y); ctx.rotate(by:a)
            ctx.beginPath()
            ctx.addArc(center:.zero, radius:avR, startAngle:0, endAngle:.pi*2, clockwise:false)
            ctx.setStrokeColor(isActive
                ? UIColor(hex:"2D7A4F").cgColor
                : UIColor(white:1, alpha:0.15).cgColor)
            ctx.setLineWidth(isActive ? 2.5 : 1.2)
            ctx.strokePath()
            ctx.restoreGState()
        }

        // ── Outer/inner border arcs ────────────────────────────────────────
        ctx.saveGState()
        ctx.setStrokeColor(UIColor(white:0.165, alpha:1).cgColor)
        ctx.setLineWidth(1.5)
        for r in [rOuter, rInner] {
            ctx.beginPath()
            ctx.addArc(center:CGPoint(x:cx,y:cy), radius:r, startAngle:c0, endAngle:c1, clockwise:false)
            ctx.strokePath()
        }

        // ── Green active-slot highlight arcs (top & bottom of center slot) ─
        let ahw = slotW / (2 * rMid) + 0.001
        ctx.setStrokeColor(UIColor(hex:"2D7A4F").cgColor)
        ctx.setLineWidth(3)
        ctx.beginPath()
        ctx.addArc(center:CGPoint(x:cx,y:cy), radius:rOuter+2, startAngle:ca(-ahw), endAngle:ca(ahw), clockwise:false)
        ctx.strokePath()
        ctx.beginPath()
        ctx.addArc(center:CGPoint(x:cx,y:cy), radius:rInner-2, startAngle:ca(-ahw), endAngle:ca(ahw), clockwise:false)
        ctx.strokePath()
        ctx.restoreGState()
    }
}

// MARK: - UIColor hex convenience (scoped to this file)

private extension UIColor {
    convenience init(hex: String) {
        var h = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        self.init(
            red:   CGFloat((int >> 16) & 0xFF) / 255,
            green: CGFloat((int >> 8)  & 0xFF) / 255,
            blue:  CGFloat(int         & 0xFF) / 255,
            alpha: 1
        )
    }
}
