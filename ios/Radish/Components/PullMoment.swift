// 拔蘿蔔的那一下。按「去過了，拔起來」之後蓋滿整個畫面：
// 蘿蔔埋在土裡 → 左右搖三下（每下一個輕震）→ 用力拔出來放大（一個重震）→ 土屑飛出去 → 出現那一句（成功的震動）。
// 整段大約兩秒，點一下可以提早關掉。開著「減少動態效果」時不搖不彈，直接淡入拔好的樣子。
// 對應 mobile/src/components/PullMoment.tsx。
// 用法：放在 `.fullScreenCover` 裡，外面加 `.presentationBackground(Color.clear)`，出現和收掉都關掉系統的滑入動畫
// （淡入淡出這裡自己做）。底是不透明的畫布色，淡入完就看不到後面的畫面。
import SwiftUI
import UIKit

private let PULL_W: CGFloat = T.Size.heroRing
private let PULL_H: CGFloat = T.Size.heroRing * 1.25

/// 這一段動畫自己的節奏（秒），只在這裡用
private enum PullMS {
    static let fade: Double = 0.16  // domy-ignore: 這一段動畫自己的節奏，只在這裡用
    static let tug: Double = 0.095  // domy-ignore: 同上
    static let settle: Double = 0.22  // domy-ignore: 同上
    static let text: Double = 0.2  // domy-ignore: 同上
    static let hold: Double = 1.1  // domy-ignore: 同上
    static let out: Double = 0.22  // domy-ignore: 同上
}

/// 蘿蔔放大的倍數與拔出來那一下的大小，只在這裡用
private enum PullSize {
    static let radish: CGFloat = 6.5  // domy-ignore: 蘿蔔放大的倍數，只在這裡用
    static let pop: CGFloat = 1.25  // domy-ignore: 拔出來那一下的大小
    static let rest: CGFloat = 1.06  // domy-ignore: 拔出來之後停著的大小
    static let scrim: Double = 1  // domy-ignore: 底的濃度。1 是完全不透明，後面的畫面不會透出來
    static let mark: Double = 0.4  // domy-ignore: 土丘上那幾條紋的濃度
    static let markLine: CGFloat = 3  // domy-ignore: 土丘上那幾條紋的粗細（土丘自己的座標）
    static let swing: Double = 9  // domy-ignore: 搖到最旁邊是幾度
    static let springStiffness: Double = 592.2  // domy-ignore: RN 的 tension 140 換算過來
    static let springDamping: Double = 16  // domy-ignore: RN 的 friction 5 換算過來
}

/// 埋著的時候往下沉多少、拔出來之後往上到哪
private let BURIED: CGFloat = PULL_H * 0.28
private let OUT: CGFloat = -PULL_H * 0.2
/// 蘿蔔和土屑的底離舞台底多高
private let LIFT: CGFloat = PULL_H * 0.3
private let MOUND_H: CGFloat = PULL_H * 0.34

/// 土屑：往哪邊飛、飛多高、多大
private struct Crumb {
    let dx: CGFloat
    let dy: CGFloat
    let r: CGFloat
}

private let CRUMBS: [Crumb] = [
    Crumb(dx: -70, dy: 60, r: 7),
    Crumb(dx: -38, dy: 92, r: 5),
    Crumb(dx: -8, dy: 70, r: 4),
    Crumb(dx: 30, dy: 96, r: 6),
    Crumb(dx: 66, dy: 58, r: 5),
    Crumb(dx: 50, dy: 30, r: 4),
    Crumb(dx: -56, dy: 26, r: 4),
]

/// 搖的每一下：歪到哪邊（-1 到 1）、往上鬆多少
private struct Tug {
    let deg: Double
    let up: CGFloat
}

private let TUGS: [Tug] = [
    Tug(deg: -1, up: 8),
    Tug(deg: 1, up: 16),
    Tug(deg: -0.7, up: 26),
    Tug(deg: 0.7, up: 38),
    Tug(deg: 0, up: 46),
]

private let MOUND: Path = svgPath("M0,92 L0,56 C24,22 70,6 108,6 C146,6 192,22 216,56 L216,92 Z")
private let MOUND_MARKS: Path = svgPath("M56,40 h14 M132,30 h18 M96,58 h10 M160,60 h12")
private let MOUND_BOX: CGRect = CGRect(x: 0, y: 0, width: 216, height: 92)

/// 等幾秒。等的時候畫面收掉了就回 false
private func pullPause(_ seconds: Double) async -> Bool {
    let nanos: UInt64 = UInt64(max(0, seconds) * 1_000_000_000)
    try? await Task.sleep(nanoseconds: nanos)
    return !Task.isCancelled
}

/// 土丘畫在蘿蔔前面，蓋住埋著的那一截
private struct PullMound: View {
    var body: some View {
        Canvas { (context: inout GraphicsContext, canvasSize: CGSize) in
            var g: GraphicsContext = context
            g.concatenate(svgFit(MOUND_BOX, canvasSize))
            g.fill(MOUND, with: .color(RadishColors.soil))
            g.stroke(
                MOUND_MARKS, with: .color(RadishColors.smallLine.opacity(PullSize.mark)),
                style: StrokeStyle(lineWidth: PullSize.markLine, lineCap: .round)
            )
        }
        .frame(width: PULL_W, height: MOUND_H)
        .accessibilityHidden(true)
    }
}

/// 一粒土屑飛出去的路：t 從 0 到 1。先往上拋，再掉下來，最後淡掉
private struct CrumbFly: ViewModifier, Animatable {
    var t: Double
    let dx: CGFloat
    let dy: CGFloat

    var animatableData: Double {
        get { return t }
        set { t = newValue }
    }

    /// TS 的 [0, 0.05, 0.7, 1] → [0, 1, 1, 0]
    private var alpha: Double {
        if t <= 0 { return 0 }
        if t < 0.05 { return t / 0.05 }
        if t <= 0.7 { return 1 }
        if t >= 1 { return 0 }
        return (1 - t) / 0.3
    }

    /// TS 的 [0, 0.45, 1] → [0, -dy, dy * 0.4]
    private var drop: CGFloat {
        let k: CGFloat = CGFloat(min(1, max(0, t)))
        if k < 0.45 { return -dy * (k / 0.45) }
        let rest: CGFloat = (k - 0.45) / 0.55
        return -dy + (dy * 0.4 + dy) * rest
    }

    func body(content: Content) -> some View {
        let k: CGFloat = CGFloat(min(1, max(0, t)))
        return content
            .opacity(alpha)
            .offset(x: dx * k, y: drop)
    }
}

struct PullMoment: View {
    let name: String
    let size: StopSize
    let line: String
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool
    @State private var fade: Double = 0
    @State private var y: CGFloat = BURIED
    @State private var tilt: Double = 0
    @State private var scale: CGFloat = 1
    @State private var crumb: Double = 0
    @State private var text: Double = 0
    @State private var closing: Bool = false

    init(name: String, size: StopSize, line: String, onDone: @escaping () -> Void) {
        self.name = name
        self.size = size
        self.line = line
        self.onDone = onDone
    }

    var body: some View {
        ZStack {
            C.canvas
                .opacity(fade * PullSize.scrim)
                .ignoresSafeArea()
            VStack(spacing: T.Space.s5) {
                stage
                words
            }
            .padding(T.Space.s6)
            .opacity(fade)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            close()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name)，\(line)點一下關掉")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            close()
        }
        .accessibilityIdentifier("pull-moment")
        .task {
            // 只在出現的那一刻跑一次
            await run()
        }
    }

    /// 蘿蔔、土丘、土屑
    private var stage: some View {
        ZStack(alignment: .bottom) {
            Radish(size: size, scale: PullSize.radish)
                .scaleEffect(scale)
                .rotationEffect(Angle.degrees(tilt * PullSize.swing))
                .padding(.bottom, LIFT)
                .offset(y: y)
            PullMound()
            ForEach(Array(CRUMBS.enumerated()), id: \.offset) { _, c in
                Circle()
                    .fill(RadishColors.soil)
                    .frame(width: c.r * 2, height: c.r * 2)
                    .padding(.bottom, LIFT)
                    .modifier(CrumbFly(t: crumb, dx: c.dx, dy: c.dy))
            }
        }
        .frame(width: PULL_W, height: PULL_H, alignment: .bottom)
    }

    /// 那一句、站名、歡呼的蘿蔔人
    private var words: some View {
        VStack(spacing: T.Space.s2) {
            DomyText(line, .title1, align: .center)
            DomyText(name, .headline, tone: .strong, align: .center)
            RadishBuddy(action: .cheer, size: BUDDY_SIZE.card)
        }
        .opacity(text)
        .offset(y: CGFloat(1 - text) * T.Space.s3)
    }

    private func close() {
        if closing { return }
        closing = true
        withAnimation(.easeOut(duration: PullMS.out)) {
            fade = 0
        }
        let done: () -> Void = onDone
        Task { @MainActor in
            let nanos: UInt64 = UInt64(PullMS.out * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            done()
        }
    }

    private func run() async {
        if reduceMotion {
            y = OUT
            scale = PullSize.rest
            withAnimation(.easeOut(duration: PullMS.fade)) {
                fade = 1
            }
            withAnimation(.easeOut(duration: PullMS.text)) {
                text = 1
            }
            Haptic.notify(.success)
            guard await pullPause(PullMS.hold + PullMS.fade) else { return }
            close()
            return
        }

        withAnimation(.easeOut(duration: PullMS.fade)) {
            fade = 1
        }
        guard await pullPause(PullMS.fade) else { return }

        // 搖三下：每一下往上鬆一點。震動跟著搖的節奏走：前三下輕震，第四下中震
        for k in 0..<TUGS.count {
            let tug: Tug = TUGS[k]
            withAnimation(.easeInOut(duration: PullMS.tug)) {
                tilt = tug.deg
            }
            withAnimation(.easeOut(duration: PullMS.tug)) {
                y = BURIED - tug.up
            }
            guard await pullPause(PullMS.tug) else { return }
            if k < 3 {
                Haptic.impact(.light)
            } else if k == 3 {
                Haptic.impact(.medium)
            }
        }

        // 用力拔出來
        Haptic.impact(.heavy)
        let spring: Animation = .interpolatingSpring(
            mass: 1, stiffness: PullSize.springStiffness, damping: PullSize.springDamping, initialVelocity: 0)
        withAnimation(spring) {
            y = OUT
        }
        let popTime: Double = PullMS.tug * 1.4
        withAnimation(.easeOut(duration: popTime)) {
            scale = PullSize.pop
        }
        withAnimation(.linear(duration: PullMS.settle * 2.4)) {
            crumb = 1
        }
        withAnimation(.easeOut(duration: PullMS.text)) {
            text = 1
        }
        guard await pullPause(popTime) else { return }
        withAnimation(.easeInOut(duration: PullMS.settle)) {
            scale = PullSize.rest
        }
        // 拔出來之後 settle + tug 秒：成功的震動
        guard await pullPause(PullMS.settle + PullMS.tug - popTime) else { return }
        Haptic.notify(.success)
        // 拔出來之後 settle + hold 秒：自己關掉
        guard await pullPause(PullMS.hold - PullMS.tug) else { return }
        close()
    }
}
