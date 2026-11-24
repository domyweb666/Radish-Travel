// 跟 AI 講的那一列（線框 A1、A1-Keyboard、A2、A19、A20）：釘在畫面最下面、懸浮分頁列上面，一直都在。
// 左邊的小標寫 AI 在看哪裡（第 3 天、今天、某一站），只是標示，不能點；右邊送出。上面一排說法照這趟走到哪換。
// 鍵盤出來時整列跟著上來（分頁列留在鍵盤後面）。送出之後升起「剛剛那一則」（ReplySheet）。
// 沒網路、句數用完時，要 AI 的說法變灰，打的字留著；手機答得出的照樣答。
// 這個檔是 SwiftUI 版才有的，mobile/ 沒有對應的 TS。
//
// 用法：`Screen(...) { ... }.talkBar("第 3 天", target: .day(3))`、`.talkBar(stop.n, target: .stop(id: id))`
import Combine
import SwiftUI
import UIKit

/// 小標最多幾個字：站名太長就截掉，不要把輸入框擠沒了
private let TALK_TAG_MAX: Int = 7
/// 輸入框最多打幾個字
let TALK_MAX: Int = 200

extension View {
    /// 把常駐的講的那一列釘在這個畫面最下面（分頁列上面）。送出之後升起「剛剛那一則」
    func talkBar(_ label: String, target: TalkTarget) -> some View {
        modifier(TalkBarPin(label: label, target: target))
    }
}

private struct TalkBarPin: ViewModifier {
    let label: String
    let target: TalkTarget
    @Environment(Sheets.self) private var sheets

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            TalkBar(label: label, target: target, ids: "talk") {
                sheets.open(.reply)
            }
        }
    }
}

/// 講的那一列本身。問 AI 分頁也用它（ids 給 "chat"，送出後不升半頁，回覆接在對話裡）
struct TalkBar: View {
    let label: String
    let target: TalkTarget
    /// 無障礙代號的開頭：這一天、一站是 talk，問 AI 分頁是 chat
    var ids: String
    /// 上面那排說法。nil 是照這趟走到哪換（AppStore.talkHints）
    var hints: [String]?
    var onSent: () -> Void

    @Environment(AppStore.self) private var store
    @FocusState private var focused: Bool
    /// 鍵盤出來了：可能是這一列叫的，也可能是同一頁別的輸入框（一站的「那一句」）
    @State private var keyboardUp: Bool = false

    init(label: String, target: TalkTarget, ids: String, hints: [String]? = nil, onSent: @escaping () -> Void) {
        self.label = label
        self.target = target
        self.ids = ids
        self.hints = hints
        self.onSent = onSent
    }

    private var text: Binding<String> {
        Binding<String>(
            get: { store.drafts[target] ?? "" },
            set: { (v: String) in
                store.drafts[target] = v.count > TALK_MAX ? String(v.prefix(TALK_MAX)) : v
            }
        )
    }

    private var typed: String {
        (store.drafts[target] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 要 AI 的句子現在送不出去
    private var hold: TalkHold? { store.talkHold }

    /// 這句現在能不能送：有字、沒在等上一句；送不出去給 AI 的時候，只有手機答得出的能送
    private func canSend(_ s: String) -> Bool {
        if s.isEmpty || store.talkBusy { return false }
        if hold != nil && store.talkNeedsAI(s, target: target) { return false }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: T.Space.s2) {
            if let line = holdLine {
                DomyText(line, .footnote, tone: .secondary)
                    .accessibilityIdentifier("\(ids)-hold")
            }
            hintRow
            inputRow
        }
        .padding(.top, T.Space.s2)
        .padding(.horizontal, T.Size.screenMargin)
        // 鍵盤收著的時候讓出懸浮分頁列；鍵盤出來時（不管哪個框叫的）分頁列在鍵盤後面，只留一點空
        .padding(.bottom, lowered ? T.Space.s2 : tabBarRoom)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(C.canvas.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Hairline() }
        .animation(Motion.transition, value: lowered)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { (note: Notification) in
            keyboardUp = coversTabBar(note)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { (_: Notification) in
            keyboardUp = false
        }
        .onAppear { keyboardUp = false }
    }

    /// 懸浮分頁列佔的高度
    private var tabBarRoom: CGFloat { T.Size.tabBarBottom + T.Size.tabBar + T.Space.s3 }

    private var lowered: Bool { focused || keyboardUp }

    /// 鍵盤有沒有高到蓋住分頁列。接實體鍵盤時只有一條或在畫面外，那就照沒有鍵盤排
    private func coversTabBar(_ note: Notification) -> Bool {
        guard let end = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return false }
        let shown: CGFloat = UIScreen.main.bounds.height - end.minY
        return shown > tabBarRoom
    }

    /// 輸入列上面那一行（A19、A20）。❓29 要不要賣、在哪賣還沒定（閘門 4），線框那格［ ］不放上來
    private var holdLine: String? {
        switch hold {
        case .offline?:
            return "沒網路：手機答得出的照樣答，要 AI 的先打好"
        case .quota?:
            return "這趟的 AI 句數用完了。手機答得出的照樣答，打的字留著。"
        case nil:
            // 走後端、算句數的時候，剩 5 句以內才講（❓29 先這樣定）
            if let left = store.talkLeft, left <= 5 {
                return "這趟還能問 AI \(left) 句。手機答得出的不算。"
            }
            return nil
        }
    }

    private var hintRow: some View {
        let list: [String] = hints ?? store.talkHints(target)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: T.Space.s2) {
                ForEach(Array(list.enumerated()), id: \.offset) { index, h in
                    Chip(h, disabled: !canSend(h)) { send(h, typedNow: false) }
                        .accessibilityIdentifier("\(ids)-hint-\(index)")
                }
            }
        }
        .scrollClipDisabled()
    }

    private var inputRow: some View {
        HStack(spacing: T.Space.s2) {
            HStack(spacing: T.Space.s2) {
                tag
                TextField("", text: text, prompt: Text("想改、想問，跟 AI 講").foregroundStyle(C.textSecondary))
                    .font(T.TypeScale.body.font)
                    .foregroundStyle(C.textPrimary)
                    .tint(C.accent)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit { send(typed, typedNow: true) }
                    .accessibilityLabel("跟 AI 講\(label)")
                    .accessibilityIdentifier("\(ids)-input")
            }
            .padding(.leading, T.Space.s1 + T.Space.s1 / 2)
            .padding(.trailing, T.Space.s3)
            .frame(maxWidth: .infinity, minHeight: T.Size.field)
            .background(C.surface, in: Capsule())
            .overlay(
                Capsule().strokeBorder(
                    focused ? C.textPrimary : C.fieldBorder,
                    lineWidth: focused ? T.Size.hairline * 2 : T.Size.hairline)
            )
            .contentShape(Capsule())
            .onTapGesture { focused = true }
            sendButton
        }
    }

    /// AI 在看哪裡。只是標示，不能點
    private var tag: some View {
        let short: String = label.count > TALK_TAG_MAX ? String(label.prefix(TALK_TAG_MAX - 1)) + "…" : label
        return DomyText(short, .footnote, weight: .semibold, lines: 1)
            .fixedSize()
            .padding(.horizontal, T.Space.s2 + T.Space.s1 / 2)
            .padding(.vertical, T.Space.s2)
            .background(C.surfaceMuted, in: Capsule())
            .accessibilityHidden(true)
    }

    private var sendButton: some View {
        let on: Bool = canSend(typed)
        return Button {
            send(typed, typedNow: true)
        } label: {
            LineIcon(IconPaths.send, color: on ? C.onAccent : C.textDisabled)
                .frame(width: T.Size.field, height: T.Size.field)
                .background(on ? C.accent : C.surfaceMuted, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!on)
        .accessibilityLabel("送出")
        .accessibilityIdentifier("\(ids)-send")
    }

    /// 送一句。typedNow 是框裡打的那句：收下了才清掉；點說法送出去的，不動框裡打到一半的字
    private func send(_ raw: String, typedNow: Bool) {
        let msg: String = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !canSend(msg) { return }
        let ok: Bool = store.talk(msg, target: target)
        if !ok { return }
        if typedNow {
            store.drafts[target] = nil
        }
        focused = false
        onSent()
    }
}
