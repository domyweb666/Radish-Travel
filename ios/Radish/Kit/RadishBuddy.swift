// 蘿蔔人：戴蘿蔔頭套的火柴人。頭套和臉用 Theme.swift 的角色色；身體線條跟著文字色，深色模式才看得到。
// 動作在 BuddyPoses.swift。這裡只管畫，和每一格往前推時間。
// 開著「減少動態效果」時不播，停在最好認的那一格。
// 照 mobile/src/components/buddy/RadishBuddy.tsx 搬。
import SwiftUI

/// 常用的三種大小，從設計代號算出來
enum BUDDY_SIZE {
    /// 開場、空畫面的主角
    static let hero: CGFloat = T.Space.s12 * 3
    /// 卡片裡陪在旁邊
    static let card: CGFloat = T.Space.s12 * 1.5
    /// 對話頭像
    static let avatar: CGFloat = T.Size.touch
}

/// full 是全身，bust 是頭和肩膀（頭像用）
enum BuddyCrop: String, Sendable {
    case full, bust
}

/// TS 的 BOX：畫面要看角色座標裡的哪一塊
private func buddyBox(_ crop: BuddyCrop) -> CGRect {
    switch crop {
    case .full: return CGRect(x: 50, y: -20, width: 220, height: 420)
    case .bust: return CGRect(x: 85, y: 12, width: 150, height: 190)
    }
}

private let BLEND: Double = 0.28  // 換動作的過渡秒數
private let FRAME: Double = 1.0 / 30.0  // 一秒畫 30 格就夠，省電

private let HOOD: Path = svgPath("M0,4 C-22,2 -46,-18 -46,-52 C-46,-84 -24,-102 0,-102 C24,-102 46,-84 46,-52 C46,-18 22,2 0,4 Z")
private let LEAF_L: Path = svgPath("M-2,-97 C-22,-106 -35,-126 -31,-146 C-14,-138 -4,-120 -2,-97 Z")
private let LEAF_M: Path = svgPath("M0,-97 C-11,-122 -7,-146 2,-160 C12,-145 12,-121 0,-97 Z")
private let LEAF_R: Path = svgPath("M2,-97 C6,-120 18,-137 35,-143 C37,-124 24,-105 2,-97 Z")
private let HOOD_SHINE: Path = svgPath("M-33,-74 C-24,-88 -12,-95 2,-96")
private let HOOD_MARKS: Path = svgPath("M30,-22 h9 M-40,-30 h8")

private func buddyPoint(_ p: Pt) -> CGPoint {
    return CGPoint(x: p.x, y: p.y)
}

private func buddyCircle(_ cx: Double, _ cy: Double, _ r: Double) -> Path {
    return Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
}

private func buddyRound(_ w: Double) -> StrokeStyle {
    return StrokeStyle(lineWidth: CGFloat(w), lineCap: .round)
}

/// TS 的 Limb：一節一節的線，兩頭是圓的
private func drawLimb(_ g: GraphicsContext, _ pts: [Pt], _ w: Double, _ color: Color) {
    if pts.count < 2 { return }
    var path: Path = Path()
    for i in 1..<pts.count {
        path.move(to: buddyPoint(pts[i - 1]))
        path.addLine(to: buddyPoint(pts[i]))
    }
    g.stroke(path, with: .color(color), style: buddyRound(w))
}

/// TS 的 Head
private func drawHead(_ g: GraphicsContext, _ p: Pose) {
    let ink: Color = BuddyColors.ink
    let ex: Double = p.lookX
    let ey: Double = p.lookY
    let mx: Double = ex * 0.5
    let my: Double = -30 + ey * 0.5
    let drip: Double = (p.t * 0.9).truncatingRemainder(dividingBy: 1)

    g.fill(LEAF_L, with: .color(RadishColors.leaf))
    g.fill(LEAF_R, with: .color(RadishColors.leaf))
    g.fill(LEAF_M, with: .color(BuddyColors.leafDark))
    g.fill(HOOD, with: .color(RadishColors.small))
    g.stroke(HOOD_SHINE, with: .color(BuddyColors.shine), style: buddyRound(5))
    g.stroke(HOOD_MARKS, with: .color(RadishColors.smallLine), style: buddyRound(3))
    g.fill(buddyCircle(0, -46, 33), with: .color(BuddyColors.faceRim))
    let face: Path = buddyCircle(0, -46, 30)
    g.fill(face, with: .color(BuddyColors.face))
    g.stroke(face, with: .color(ink), style: StrokeStyle(lineWidth: 3))

    let sides: [Double] = [-1, 1]
    for sx in sides {
        let cx: Double = sx * 11 + ex
        let cy: Double = -48 + ey
        let h: Double = max(1.5, p.eyeH)
        let bx: Double = sx * 12 + ex * 0.5
        let by: Double = -61 + p.browY + ey * 0.5
        let br: Double = (p.brow * Double.pi) / 180
        let c: Double = 8 * cos(br)
        let sn: Double = 8 * sin(br)
        if p.happy > 0.5 {
            var eye: Path = Path()
            eye.move(to: CGPoint(x: cx - 5, y: cy + 3))
            eye.addQuadCurve(to: CGPoint(x: cx + 5, y: cy + 3), control: CGPoint(x: cx, y: cy - 6))
            g.stroke(eye, with: .color(ink), style: buddyRound(3.6))
        } else {
            // SVG 的 rx=2.3：高度不到 4.6 時，上下的圓角會縮成高度的一半（眨眼那一格是扁的橢圓）
            let rect: CGRect = CGRect(x: cx - 2.3, y: cy - h / 2, width: 4.6, height: h)
            let corner: CGSize = CGSize(width: 2.3, height: min(2.3, h / 2))
            g.fill(Path(roundedRect: rect, cornerSize: corner), with: .color(ink))
        }
        var browPath: Path = Path()
        browPath.move(to: CGPoint(x: bx - sx * c, y: by + sn))
        browPath.addLine(to: CGPoint(x: bx + sx * c, y: by - sn))
        g.stroke(browPath, with: .color(ink), style: buddyRound(3.4))
    }

    switch p.mouth {
    case .smile:
        var m: Path = Path()
        m.move(to: CGPoint(x: mx - 6, y: my - 1))
        m.addQuadCurve(to: CGPoint(x: mx + 6, y: my - 1), control: CGPoint(x: mx, y: my + 5))
        g.stroke(m, with: .color(ink), style: buddyRound(3))
    case .open:
        var m: Path = Path()
        m.move(to: CGPoint(x: mx - 7, y: my - 2))
        m.addQuadCurve(to: CGPoint(x: mx + 7, y: my - 2), control: CGPoint(x: mx, y: my + 10))
        m.closeSubpath()
        g.fill(m, with: .color(ink))
    case .wavy:
        // M mx-7,my q3.5,-4 7,0 t7,0：第二段的控制點是第一段的對稱點
        var m: Path = Path()
        m.move(to: CGPoint(x: mx - 7, y: my))
        m.addQuadCurve(to: CGPoint(x: mx, y: my), control: CGPoint(x: mx - 3.5, y: my - 4))
        m.addQuadCurve(to: CGPoint(x: mx + 7, y: my), control: CGPoint(x: mx + 3.5, y: my + 4))
        g.stroke(m, with: .color(ink), style: buddyRound(3))
    case .o:
        g.stroke(buddyCircle(mx, my, 2.6), with: .color(ink), style: StrokeStyle(lineWidth: 2.6))
    case .flat:
        var m: Path = Path()
        m.move(to: CGPoint(x: mx - 5, y: my))
        m.addLine(to: CGPoint(x: mx + 5, y: my))
        g.stroke(m, with: .color(ink), style: buddyRound(3))
    }

    if p.sweat > 0.5 {
        // M-21,Y q-4,7 0,9 q4,-2 0,-9 Z
        let y0: Double = -66 + drip * 6
        var drop: Path = Path()
        drop.move(to: CGPoint(x: -21, y: y0))
        drop.addQuadCurve(to: CGPoint(x: -21, y: y0 + 9), control: CGPoint(x: -25, y: y0 + 7))
        drop.addQuadCurve(to: CGPoint(x: -21, y: y0), control: CGPoint(x: -17, y: y0 + 7))
        drop.closeSubpath()
        g.fill(drop, with: .color(BuddyColors.sweat.opacity(1 - drip * 0.6)))
    }
}

/// TS 的 Figure。context 進來時已經是角色的座標（viewBox）
private func drawFigure(_ context: GraphicsContext, _ p: Pose, _ crop: BuddyCrop, _ line: Color) {
    let k: Skeleton = skeleton(p)
    let sy: Double = 1 - p.squash
    let sx: Double = 1 + p.squash * 0.6
    let shrink: Double = 1 - k.lift * 0.35

    if crop == .full {
        let rx: Double = 62 * shrink
        let ry: Double = 8 * shrink
        let shadow: Path = Path(ellipseIn: CGRect(x: RIG.hipX - rx, y: RIG.ground + 7 - ry, width: rx * 2, height: ry * 2))
        context.fill(shadow, with: .color(line.opacity(0.16 * (1 - k.lift * 0.5))))
    }

    // translate(hipX, ground) scale(sx, sy) translate(-hipX, -ground)：以腳底為中心壓扁
    var g: GraphicsContext = context
    g.translateBy(x: CGFloat(RIG.hipX), y: CGFloat(RIG.ground))
    g.scaleBy(x: CGFloat(sx), y: CGFloat(sy))
    g.translateBy(x: CGFloat(-RIG.hipX), y: CGFloat(-RIG.ground))

    for leg in k.legs {
        drawLimb(g, leg, 9, line)
    }
    drawLimb(g, [k.hip, k.neck], 9, line)

    // translate(head.x, head.y) rotate(head.rot) scale(1, head.scaleY)
    var hg: GraphicsContext = g
    hg.translateBy(x: CGFloat(k.head.x), y: CGFloat(k.head.y))
    hg.rotate(by: Angle.degrees(k.head.rot))
    hg.scaleBy(x: 1, y: CGFloat(k.head.scaleY))
    drawHead(hg, p)

    for arm in k.arms {
        drawLimb(g, arm, 8.5, line)
    }

    if p.bubble > 0.5 {
        let bubbles: [(dx: Double, dy: Double, r: Double)] = [
            (dx: -58, dy: -104, r: 4),
            (dx: -70, dy: -120, r: 5.5),
            (dx: -86, dy: -140, r: 7.5),
        ]
        for i in 0..<bubbles.count {
            let b: (dx: Double, dy: Double, r: Double) = bubbles[i]
            let alpha: Double = 0.35 + 0.65 * max(0, sin(p.t * 3 - Double(i) * 0.9))
            g.fill(
                buddyCircle(k.neck.x + b.dx, k.neck.y + b.dy, b.r),
                with: .color(RadishColors.smallLine.opacity(alpha))
            )
        }
    }
}

/// TS 裡 useRef 放的那包東西：時鐘、現在播的動作、過渡從哪個姿勢來。
/// 不是畫面狀態，改它不會讓畫面重畫；重畫是 TimelineView 每一格叫的。
private final class BuddyClock {
    private var ready: Bool = false
    private var clock: Double = 0
    private var start: Double = 0
    private var switchAt: Double = -1
    private var from: Pose = basePose()
    private var shown: Pose = basePose()
    private var action: BuddyAction = .idle
    private var dir: PointDir = .right
    private var last: Date? = nil

    /// 第一次用：停在最好認的那一格，跟 TS 的 useState 初始值一樣
    private func prepare(_ action: BuddyAction, _ dir: PointDir) {
        if ready { return }
        ready = true
        self.action = action
        self.dir = dir
        let p: Pose = poseAt(action, STILL_AT[need: action], dir)
        from = p
        shown = p
    }

    /// 「減少動態效果」開著：不播，停在靜止格。現在播的動作不更新，所以關掉之後會從靜止格過渡過去
    func still(_ action: BuddyAction, _ dir: PointDir) -> Pose {
        prepare(action, dir)
        let p: Pose = poseAt(action, STILL_AT[need: action], dir)
        shown = p
        last = nil
        return p
    }

    /// 往前推到 now，回傳這一格的姿勢
    func tick(_ now: Date, _ action: BuddyAction, _ dir: PointDir) -> Pose {
        prepare(action, dir)
        if self.action != action || self.dir != dir {
            from = shown
            switchAt = clock
            start = clock
            self.action = action
            self.dir = dir
        }
        guard let before = last else {
            last = now
            return shown
        }
        let dt: Double = min(0.1, now.timeIntervalSince(before))
        if dt <= 0 { return shown }
        last = now
        clock += dt
        var p: Pose = poseAt(self.action, clock - start, self.dir)
        if switchAt >= 0 {
            let k: Double = (clock - switchAt) / BLEND
            if k < 1 {
                p = blend(from, p, k * k * (3 - 2 * k))
            } else {
                switchAt = -1
            }
        }
        shown = p
        return p
    }
}

/// 蘿蔔人。action 換了會自己用 0.28 秒過渡過去。
/// 它是裝飾，VoiceOver 會跳過；要讓人知道的事請寫在旁邊的文字裡。
struct RadishBuddy: View {
    let action: BuddyAction
    let dir: PointDir
    /// 高度。寬度照比例算
    let size: CGFloat
    /// full 是全身，bust 是頭和肩膀（頭像用）
    let crop: BuddyCrop

    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool
    @State private var st: BuddyClock = BuddyClock()

    init(action: BuddyAction = .idle, dir: PointDir = .right, size: CGFloat = BUDDY_SIZE.card, crop: BuddyCrop = .full) {
        self.action = action
        self.dir = dir
        self.size = size
        self.crop = crop
    }

    private func figure(_ p: Pose) -> some View {
        let which: BuddyCrop = self.crop
        let box: CGRect = buddyBox(which)
        return Canvas { (context: inout GraphicsContext, canvasSize: CGSize) in
            var g: GraphicsContext = context
            g.concatenate(svgFit(box, canvasSize))
            drawFigure(g, p, which, C.textPrimary)
        }
    }

    var body: some View {
        let box: CGRect = buddyBox(crop)
        let w: CGFloat = (size * box.width) / box.height
        return Group {
            if reduceMotion {
                figure(st.still(action, dir))
            } else {
                TimelineView(.animation(minimumInterval: FRAME, paused: false)) { timeline in
                    figure(st.tick(timeline.date, action, dir))
                }
            }
        }
        .frame(width: w, height: size)
        .accessibilityHidden(true)
    }
}

/// 播一下某個動作再回到平常的樣子。例：按「拔起來」之後歡呼一秒半。
/// TS 的 useBuddyBurst。用法：
///   @State private var burst = BuddyBurst()        // 平常的樣子不是 idle 就寫 BuddyBurst(.think)
///   RadishBuddy(action: burst.action)
///   burst.play(.cheer)                              // 或 burst.play(.cheer, seconds: 1.5)
@MainActor
@Observable
final class BuddyBurst {
    var action: BuddyAction
    private let base: BuddyAction
    @ObservationIgnored private var timer: Task<Void, Never>? = nil

    init(_ base: BuddyAction = .idle) {
        self.base = base
        self.action = base
    }

    func play(_ a: BuddyAction, seconds: Double = 1.6) {
        timer?.cancel()
        action = a
        let nanos: UInt64 = UInt64(max(0, seconds) * 1_000_000_000)
        timer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanos)
            if Task.isCancelled { return }
            self?.finish()
        }
    }

    private func finish() {
        action = base
        timer = nil
    }
}
