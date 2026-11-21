// 操作說明：把畫面蓋暗，只留一塊亮的，旁邊一張卡講這一塊是做什麼的。一次講一件事。
// 要照亮的那一塊不在畫面上時，先捲過去再量位置。
// 對應 mobile/src/components/Spotlight.tsx。
// RN 版是拿元件的 ref 去量；這裡改成每一塊自己用 .spotTarget("名字", in: frames) 回報在螢幕上的框，
// 說明卡用 .fullScreenCover（透明底）蓋在最上面，連分頁列一起蓋暗。
import SwiftUI

/// 要照亮的每一塊現在在螢幕上的框（global 座標）。不是畫面狀態，改它不會讓畫面重畫；
/// 等於 TS 的 ref，要用的時候才來讀
final class SpotFrames {
    var rects: [String: CGRect] = [:]
}

/// 一步：key 是那一塊的名字（同時也是捲動用的 id），text 是說明卡上的字
struct SpotStep {
    let key: String
    let text: String
}

extension View {
    /// 標成可以被照亮的一塊：加上捲動用的 id，位置一變就記到 frames 裡
    func spotTarget(_ key: String, in frames: SpotFrames) -> some View {
        self
            .id(key)
            .onGeometryChange(for: CGRect.self) { (proxy: GeometryProxy) -> CGRect in
                return proxy.frame(in: .global)
            } action: { (rect: CGRect) in
                frames.rects[key] = rect
            }
    }
}

private let SHADE: Color = Color.black  // domy-ignore: 暗幕的顏色，只在這裡用
private let DIM: Double = 0.6  // 暗幕的濃度
private let SETTLE: Double = T.Motion.pressDuration * 2  // 等畫面排好、捲好再量
private let PAD: CGFloat = T.Space.s2
private let LOW: CGFloat = 0.55  // 那一塊的下緣超過畫面高度的這個比例，就先捲過去

/// 等幾秒。等的時候被取消（換下一步、畫面收掉）就回 false
private func spotPause(_ seconds: Double) async -> Bool {
    let nanos: UInt64 = UInt64(max(0, seconds) * 1_000_000_000)
    try? await Task.sleep(nanoseconds: nanos)
    return !Task.isCancelled
}

/// 用法：放在 `.fullScreenCover` 裡，外面再加 `.presentationBackground(Color.clear)`。
/// onScroll：要捲到哪一塊（給 nil 是清掉），由外面交給 Screen 的 scrollTo。
/// onDone：看完或按「不用看了」。
struct Spotlight: View {
    let steps: [SpotStep]
    let frames: SpotFrames
    let onScroll: (String?) -> Void
    let onDone: () -> Void

    @State private var i: Int = 0
    @State private var hole: CGRect? = nil
    @State private var shown: Bool = false
    @State private var leaving: Bool = false

    init(steps: [SpotStep], frames: SpotFrames, onScroll: @escaping (String?) -> Void, onDone: @escaping () -> Void) {
        self.steps = steps
        self.frames = frames
        self.onScroll = onScroll
        self.onDone = onDone
    }

    var body: some View {
        GeometryReader { (safe: GeometryProxy) in
            let top: CGFloat = safe.safeAreaInsets.top + T.Space.s2
            GeometryReader { (full: GeometryProxy) in
                layer(full.size, full.frame(in: .global).origin)
                    .task(id: i) {
                        await locate(top, full.size.height)
                    }
            }
            .ignoresSafeArea()
        }
        .opacity(shown ? 1 : 0)
        .onAppear {
            withAnimation(Motion.transition) {
                shown = true
            }
        }
    }

    private func next() {
        if i + 1 < steps.count {
            hole = nil
            i += 1
        } else {
            finish()
        }
    }

    /// 淡出之後才告訴外面結束了
    private func finish() {
        if leaving { return }
        leaving = true
        withAnimation(Motion.transition) {
            shown = false
        }
        let done: () -> Void = onDone
        Task { @MainActor in
            let nanos: UInt64 = UInt64(T.Motion.transition * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            done()
        }
    }

    /// 找這一步要照亮的那一塊在哪。top 是畫面上緣可以用的地方，height 是整個畫面的高
    private func locate(_ top: CGFloat, _ height: CGFloat) async {
        hole = nil
        onScroll(nil)
        guard i < steps.count else { return }
        let key: String = steps[i].key
        guard await spotPause(SETTLE) else { return }
        // 這一塊現在不在畫面上（例如那天沒有排站），跳過
        guard let first = frames.rects[key] else {
            next()
            return
        }
        if first.minY < top || first.maxY > height * LOW {
            onScroll(key)
            guard await spotPause(T.Motion.transition + SETTLE) else { return }
            guard let second = frames.rects[key] else {
                next()
                return
            }
            hole = second
        } else {
            hole = first
        }
    }

    /// 亮的那一塊，換成這一層自己的座標，四邊各多留一點
    private func holeIn(_ size: CGSize, _ origin: CGPoint) -> CGRect? {
        guard let raw = hole else { return nil }
        let x: CGFloat = max(0, raw.minX - origin.x - PAD)
        let y: CGFloat = raw.minY - origin.y - PAD
        let w: CGFloat = min(size.width, raw.width + PAD * 2)
        let h: CGFloat = raw.height + PAD * 2
        return CGRect(x: x, y: y, width: w, height: h)
    }

    @ViewBuilder
    private func layer(_ size: CGSize, _ origin: CGPoint) -> some View {
        if i < steps.count {
            ZStack(alignment: .topLeading) {
                if let rect = holeIn(size, origin) {
                    shade(size, rect)
                    ring(rect)
                    card(size, rect)
                } else {
                    SHADE.opacity(DIM)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .accessibilityAddTraits(.isModal)
        }
    }

    /// 整片暗幕，中間挖掉亮的那一塊
    private func shade(_ size: CGSize, _ rect: CGRect) -> some View {
        var path: Path = Path()
        path.addRect(CGRect(x: 0, y: 0, width: size.width, height: size.height))
        path.addRect(rect)
        return path
            .fill(SHADE.opacity(DIM), style: FillStyle(eoFill: true))
            .accessibilityHidden(true)
    }

    private func ring(_ rect: CGRect) -> some View {
        RoundedRectangle(cornerRadius: T.Radius.md, style: .continuous)
            .strokeBorder(C.bright, lineWidth: T.Size.hairline * 3)
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// 說明卡：亮的那一塊在上半就放它下面，在下半就放它上面
    private func card(_ size: CGSize, _ rect: CGRect) -> some View {
        let below: Bool = rect.midY < size.height / 2
        let topPad: CGFloat = below ? max(0, rect.maxY + T.Space.s3) : 0
        let bottomPad: CGFloat = below ? 0 : max(0, size.height - rect.minY + T.Space.s3)
        return VStack(spacing: 0) {
            if !below {
                Spacer(minLength: 0)
            }
            cardBody
            if below {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, T.Size.screenMargin)
        .padding(.top, topPad)
        .padding(.bottom, bottomPad)
        .frame(width: size.width, height: size.height)
    }

    private var cardBody: some View {
        let last: Bool = i == steps.count - 1
        let text: String = i < steps.count ? steps[i].text : ""
        return Card {
            DomyText("\(i + 1)／\(steps.count)", .footnote, tone: .secondary)
            DomyText(text, .body)
            DomyButton(last ? "知道了" : "下一個", fullWidth: true) {
                next()
            }
            .accessibilityIdentifier("guide-next")
            if !last {
                DomyButton("不用看了", variant: .plain, size: .compact) {
                    finish()
                }
                .accessibilityIdentifier("guide-skip")
                .frame(maxWidth: .infinity)
            }
        }
    }
}
