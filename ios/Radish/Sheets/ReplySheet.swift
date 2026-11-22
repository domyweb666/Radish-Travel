// 剛剛那一則（S05，線框 A3、A21、New-Consent）：這一天或一站最下面講完一句，從下面升起來的半頁。
// 上半還看得到這一天。寫這次改了什麼或答案、可以復原這次、看整段對話（切到問 AI 分頁）。
// 要確認的改動顯示確認卡（Permit.swift 的權限表），按「套用」才改。
// 第一次要送給 AI 時先在這裡講清楚送什麼（S03）；沒收到回覆時這趟不動，可以再送一次。
// 對話裡一則一則的樣子（我說的、回的、確認卡、這次改了）也在這個檔，問 AI 分頁（AskScreen）共用。
// 這個檔是 SwiftUI 版才有的；確認卡、這次改了照原本的 mobile/src/sheets/ChatSheet.tsx。
import SwiftUI

/// 送給 AI 的有哪些。第一次的說明、平常的我的「送給 AI 的資料」都用這份。照 aiPrompt 真的送的寫（❓23）
let AI_SENDS: [String] = [
    "這趟的行程：日期、每天排的站、幾個人、住哪一帶；旅途中還有今天第幾天、現在幾點、拔過哪幾站",
    "平常的我裡的習慣，包括過敏和不吃的",
    "前面幾句你跟 AI 說的話",
]
let AI_NOT_SENT: String = "不會送：手機的定位、名字、聯絡方式、照片。"
/// 送去哪裡：平常的我填了 Claude API 金鑰就直接送 Anthropic，沒填就經過蘿蔔旅行的後端
var AI_WHERE: String {
    if !CLAUDE_KEY.isEmpty {
        return "這些會用你在平常的我填的 Claude API 金鑰，直接送到 Anthropic 的 Claude，不經過蘿蔔旅行。費用算在那把金鑰的 Anthropic 帳戶。"
    }
    return "這些會送到蘿蔔旅行的伺服器，再轉給 AI 服務（Anthropic 的 Claude）。"
}

/// 幾點說的：兩分鐘內寫「剛剛」，今天寫幾點幾分，更早的加日期
private func talkWhen(_ at: Double) -> String {
    let date: Date = Date(timeIntervalSince1970: at)
    if Date().timeIntervalSince(date) < 120 { return "剛剛" }
    let f: DateFormatter = DateFormatter()
    f.locale = Locale(identifier: "zh_Hant_TW")
    f.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "M/d HH:mm"
    return f.string(from: date)
}

/// 這則是誰說的（02-流程 9-6）。手機算的、AI 說的要分得出來；舊的存檔沒記的就不標
func talkSource(_ m: ChatMsg) -> String? {
    if m.local == true { return "手機算的，沒有問 AI" }
    if let at = m.at { return "AI 說的・\(talkWhen(at))" }
    return nil
}

/// 一條前面帶點的字
private struct TalkBullet: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: T.Space.s2) {
            DomyText("・", .body, tone: .secondary)
            DomyText(text, .body).fillLeading()
        }
    }
}

/// 我說的那一句：靠右、產品色
struct TalkMine: View {
    let text: String

    var body: some View {
        DomyText(text, .body, tone: .onAccent)
            .padding(.vertical, T.Space.s3)
            .padding(.horizontal, T.Space.s4)
            .background(C.accent, in: RoundedRectangle(cornerRadius: T.Radius.xl, style: .continuous))
            .padding(.leading, T.Space.s12)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// 一行小字：哪幾步沒做成、提醒
struct TalkNote: View {
    let text: String

    var body: some View {
        DomyText(text, .footnote, tone: .secondary)
            .padding(.horizontal, T.Space.s2)
            .fillLeading()
    }
}

/// 「這次改了」清單
private struct TalkChanges: View {
    let changes: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: T.Space.s1) {
            DomyText("這次改了", .caption, tone: .secondary)
            ForEach(Array(changes.enumerated()), id: \.offset) { _, ch in
                DomyText(ch, .subheadline, tone: .strong)
            }
        }
        .padding(.top, T.Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Hairline() }
    }
}

/// 確認卡：這幾樣要按「套用」才改。按過了只留結果
private struct TalkAsk: View {
    let index: Int
    let m: ChatMsg
    let lines: [String]
    @Environment(AppStore.self) private var store

    private var head: String {
        if m.askOps != nil { return "要你點頭才改" }
        return m.asked == true ? "套用了" : "沒套用"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: T.Space.s2) {
            DomyText(head, .caption, tone: .secondary)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                DomyText(line, .subheadline, tone: m.askOps != nil ? .strong : .secondary)
            }
            if m.askOps != nil {
                HStack(spacing: T.Space.s2) {
                    DomyButton("套用", size: .compact, haptic: true) { store.confirmAsk(index) }
                        .accessibilityIdentifier("chat-ask-apply")
                    DomyButton("不要", variant: .secondary, size: .compact) { store.skipAsk(index) }
                        .accessibilityIdentifier("chat-ask-skip")
                }
                .padding(.top, T.Space.s1)
            }
        }
        .padding(.top, T.Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Hairline() }
    }
}

/// 這一輪能不能復原：還是最後一步就給按鈕，不然寫為什麼不能
struct TalkUndo: View {
    let index: Int
    let m: ChatMsg
    /// 按鈕的無障礙代號
    let id: String
    var fullWidth: Bool = false
    @Environment(AppStore.self) private var store

    init(index: Int, m: ChatMsg, id: String, fullWidth: Bool = false) {
        self.index = index
        self.m = m
        self.id = id
        self.fullWidth = fullWidth
    }

    /// 這一輪有改到行程，才有復原這回事
    static func applies(_ m: ChatMsg) -> Bool {
        return !(m.changes ?? []).isEmpty && m.undo != nil
    }

    var body: some View {
        if m.undone == true {
            DomyText("這次復原了", .footnote, tone: .secondary)
        } else if store.canUndoRound(m) {
            DomyButton("復原這次", variant: .secondary, size: fullWidth ? .regular : .compact, fullWidth: fullWidth) {
                store.undoRound(index)
            }
            .accessibilityIdentifier(id)
        } else {
            DomyText("之後又改過了", .footnote, tone: .secondary)
        }
    }
}

/// 回的那一則：誰說的、說了什麼、這次改了、確認卡。
/// inline 為 true（問 AI 分頁）時，「看第 N 天」和「復原這次」放在這一則裡面
struct TalkAnswer: View {
    let index: Int
    let m: ChatMsg
    var inline: Bool = false
    var seeDay: ((Int) -> Void)?

    var body: some View {
        let changes: [String] = m.changes ?? []
        VStack(alignment: .leading, spacing: T.Space.s2) {
            if let source = talkSource(m) {
                DomyText(source, .caption, tone: .secondary)
            }
            DomyText(m.t, .body)
            if !changes.isEmpty {
                TalkChanges(changes: changes)
            }
            if let ask = m.ask, !ask.isEmpty {
                TalkAsk(index: index, m: m, lines: ask)
            }
            if inline {
                actions
            }
        }
        .padding(.vertical, T.Space.s3)
        .padding(.horizontal, T.Space.s4)
        .background(C.surface, in: RoundedRectangle(cornerRadius: T.Radius.xl, style: .continuous))
        .padding(.trailing, inline ? T.Space.s12 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var actions: some View {
        let undo: Bool = TalkUndo.applies(m)
        if (seeDay != nil && m.day != nil) || undo {
            HStack(spacing: T.Space.s2) {
                if let seeDay, let day = m.day, !(m.changes ?? []).isEmpty {
                    DomyButton("看第 \(day) 天", variant: .plain, size: .compact) { seeDay(day) }
                        .accessibilityIdentifier("chat-see-day-\(index)")
                }
                if undo {
                    TalkUndo(index: index, m: m, id: "chat-undo-\(index)")
                }
            }
        }
    }
}

/// 第一次要送給 AI 的說明（S03，線框 New-Consent）。按「同意並送出」才送；先不要的話，講的字留著
struct TalkConsent: View {
    let text: String
    let onDecline: () -> Void
    @Environment(AppStore.self) private var store

    init(text: String, onDecline: @escaping () -> Void) {
        self.text = text
        self.onDecline = onDecline
    }

    var body: some View {
        VStack(alignment: .leading, spacing: T.Space.s3) {
            DomyText("送出之前，先講清楚", .title2)
                .accessibilityAddTraits(.isHeader)
            DomyText("按「同意並送出」之後，會送出下面這些。\(AI_WHERE)", .body)
            VStack(alignment: .leading, spacing: T.Space.s2) {
                TalkBullet(text: "你講的這句：「\(text)」")
                ForEach(Array(AI_SENDS.enumerated()), id: \.offset) { _, line in
                    TalkBullet(text: line)
                }
            }
            DomyText(AI_NOT_SENT, .body)
            DomyText("只有第一次會問。之後在「平常的我」可以收回。", .footnote, tone: .secondary)
            DomyButton("同意並送出", fullWidth: true) {
                store.talkConsent()
            }
            .accessibilityIdentifier("chat-consent")
            DomyButton("先不要", variant: .secondary, fullWidth: true) {
                store.talkDecline()
                onDecline()
            }
            .accessibilityIdentifier("chat-consent-no")
            DomyText("先不要的話，你講的都留著。", .footnote, tone: .secondary)
        }
    }
}

struct ReplySheet: View {
    @Environment(AppStore.self) private var store
    @Environment(Sheets.self) private var sheets
    @Environment(Nav.self) private var nav

    init() {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: T.Space.s4) {
                content
            }
            .padding(.horizontal, T.Size.screenMargin)
            .padding(.top, T.Space.s6)
            .padding(.bottom, T.Space.s6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(C.canvas.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onDisappear { store.talkDismiss() }
    }

    @ViewBuilder private var content: some View {
        switch store.talkStage {
        case .consent(let text, _):
            TalkConsent(text: text) { sheets.close() }
        case .held(let why):
            held(why)
        case .idle, .busy:
            if let me = store.lastTalk, me < store.s.chat.count {
                round(me)
            } else {
                DomyText("還沒有講過話。", .body, tone: .secondary)
                closeButton("好")
            }
        }
    }

    /// 要 AI 的那句沒送出去（沒網路、句數用完）。字已經留在講的那一列
    @ViewBuilder private func held(_ why: TalkHold) -> some View {
        switch why {
        case .offline:
            DomyText("沒網路，這句還沒送出去，這趟沒有動。", .headline)
            DomyText("打的字留在講的那一列，連上網路再送。手機答得出的照樣答。", .body, tone: .secondary)
        case .quota:
            // ❓29：要不要賣、在哪賣，閘門 4 定。線框那格［ ］不放上來
            DomyText("這趟的 AI 句數用完了。這句沒有送出去，這趟沒有動。", .headline)
            DomyText("手機答得出的照樣答，打的字留著。", .body, tone: .secondary)
        }
        closeButton("好")
    }

    /// 最後一輪：我說的，下面是回的（或等回覆、沒收到回覆）
    @ViewBuilder private func round(_ me: Int) -> some View {
        let m: ChatMsg = store.s.chat[me]
        let after: [Int] = Array((me + 1)..<store.s.chat.count)
        TalkMine(text: m.t)
        if let code = m.failed {
            failed(me, code)
        } else if after.isEmpty {
            DomyText(store.talkBusy ? "想一下…" : "這句沒有回覆。", .body, tone: .secondary)
            closeButton("好，收起來")
        } else {
            ForEach(after, id: \.self) { (i: Int) in
                reply(i)
            }
            footer(after)
        }
    }

    @ViewBuilder private func reply(_ i: Int) -> some View {
        let m: ChatMsg = store.s.chat[i]
        if m.r == .sys {
            TalkNote(text: m.t)
        } else {
            TalkAnswer(index: i, m: m)
        }
    }

    /// 好，收起來、復原這次；下面看整段對話
    @ViewBuilder private func footer(_ after: [Int]) -> some View {
        let ai: Int? = after.first { (i: Int) -> Bool in store.s.chat[i].r == .ai }
        HStack(spacing: T.Space.s2) {
            closeButton("好，收起來")
            if let ai, TalkUndo.applies(store.s.chat[ai]) {
                TalkUndo(index: ai, m: store.s.chat[ai], id: "reply-undo", fullWidth: true)
            }
        }
        openAskButton
    }

    /// 沒收到回覆（線框 A21）：這趟沒有動，可以再送一次
    @ViewBuilder private func failed(_ me: Int, _ code: String) -> some View {
        Card {
            DomyText("這句沒有收到回覆，這趟沒有動。", .headline)
            // ❓28：這次算不算句數，等收費方式定了再寫
            if !code.isEmpty {
                DomyText("錯誤代碼：\(code)", .footnote, tone: .secondary)
            }
        }
        DomyButton("再送一次", disabled: store.talkBusy, fullWidth: true) {
            store.retryTalk(me)
        }
        .accessibilityIdentifier("reply-retry")
        DomyButton("好，先不改", variant: .secondary, fullWidth: true) {
            sheets.close()
        }
        .accessibilityIdentifier("reply-skip")
        openAskButton
    }

    private func closeButton(_ title: String) -> some View {
        DomyButton(title, fullWidth: true) {
            sheets.close()
        }
        .accessibilityIdentifier("reply-done")
    }

    private var openAskButton: some View {
        DomyButton("看整段對話", variant: .plain, size: .compact) {
            sheets.close()
            nav.show(.ask)
        }
        .accessibilityIdentifier("reply-open-ask")
    }
}
