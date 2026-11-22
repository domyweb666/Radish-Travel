// 用講的改行程。每次改完，在對話裡列出哪一站從哪到哪，可以復原上一步。
// 對應 mobile/src/sheets/ChatSheet.tsx、mobile/src/io/aiEndpoint.ts。
// AI 端點：Swift 版的 AI_ENDPOINT（Chat.swift）在 app 啟動時從 Info.plist 讀進來，已經是完整網址，
// 所以 aiEndpoint.ts 那段「補開發伺服器位址」不用搬，askRemote 直接用 AI_ENDPOINT。
import SwiftUI

private let FIRST: String = "行程排好了。想怎麼改直接說，例如哪天太滿、哪一站不想去、想多一點什麼。我改完會列出動了哪幾站。"

/// 輸入框最多打幾個字
private let CHAT_MAX: Int = 200
/// 對話最多留幾句
private let CHAT_KEEP: Int = 40
/// 捲到底用的記號
private let CHAT_END: String = "chat-end"

/// 一句對話。sys 是一行小字；我說的靠右、產品色；AI 說的靠左、白底，下面列這次改了什麼
private struct Bubble: View {
    let m: ChatMsg

    var body: some View {
        if m.r == .sys {
            DomyText(m.t, .footnote, tone: .secondary)
                .padding(.horizontal, T.Space.s2)
                .fillLeading()
        } else {
            balloon
        }
    }

    private var balloon: some View {
        let me: Bool = m.r == .me
        let changes: [String] = m.changes ?? []
        let shape = RoundedRectangle(cornerRadius: T.Radius.xl, style: .continuous)
        return VStack(alignment: .leading, spacing: T.Space.s2) {
            DomyText(m.t, .body, tone: me ? .onAccent : .primary)
            if !changes.isEmpty {
                BubbleChanges(changes: changes)
            }
        }
        .padding(.vertical, T.Space.s3)
        .padding(.horizontal, T.Space.s4)
        .background(me ? C.accent : C.surface, in: shape)
        // TS 是 maxWidth 86%：對面那一側留一段空
        .padding(me ? .leading : .trailing, T.Space.s12)
        .frame(maxWidth: .infinity, alignment: me ? .trailing : .leading)
    }
}

/// 泡泡裡的「這次改了」清單
private struct BubbleChanges: View {
    let changes: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: T.Space.s1) {
            DomyText("這次改了", .caption, tone: .secondary)
            ForEach(Array(changes.enumerated()), id: \.offset) { _, ch in
                DomyText(ch, .subheadline, tone: .strong)
            }
        }
        .padding(.top, T.Space.s2)
        .overlay(alignment: .top) { Hairline() }
    }
}

struct ChatSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(Sheets.self) private var sheets
    @State private var text: String = ""
    @State private var busy: Bool = false

    init() {}

    private var remote: Bool { aiReady() }
    private var needConsent: Bool { remote && !store.s.aiConsent }
    private var hints: [String] { remote ? AI_HINTS : LOCAL_HINTS }
    private var typed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSend: Bool { !typed.isEmpty && !busy }

    var body: some View {
        if store.s.trip != nil {
            SheetScaffold("用講的改行程", scroll: false, onClose: { sheets.close() }) {
                if needConsent {
                    consentCard
                } else {
                    talk
                    hintRow
                    inputRow
                    DomyText(
                        remote ? "已接上 AI。它不知道即時的營業時間和票價，去之前查一下。" : "這一版還沒接上 AI，只聽得懂上面那幾種說法。",
                        .footnote, tone: .secondary)
                }
            }
        }
    }

    private var consentCard: some View {
        Card {
            DomyText("第一次用之前，先講清楚", .headline)
            DomyText("用講的改行程時，這三樣會送到蘿蔔旅行的伺服器，再轉給 AI 服務（Anthropic 的 Claude）：你打的那句話、這趟的行程、「我」分頁裡平常的習慣。", .body)
            DomyText("不會送你的位置、名字、聯絡方式。", .body)
            DomyButton("知道了，開始用", fullWidth: true) {
                store.mutate { (d: inout AppState) -> Void in
                    d.aiConsent = true
                }
            }
            .accessibilityIdentifier("chat-consent")
        }
    }

    /// 中間的對話。有新的一句、或開始等回覆時捲到底
    private var talk: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: T.Space.s2) {
                    HStack(alignment: .bottom, spacing: T.Space.s2) {
                        RadishBuddy(action: busy ? .think : .idle, size: BUDDY_SIZE.avatar, crop: .bust)
                        Bubble(m: ChatMsg(r: .ai, t: FIRST))
                    }
                    ForEach(Array(store.s.chat.enumerated()), id: \.offset) { _, m in
                        Bubble(m: m)
                    }
                    if busy {
                        Bubble(m: ChatMsg(r: .ai, t: "想一下…"))
                    }
                    Color.clear.frame(height: 0).id(CHAT_END)
                }
                .padding(.vertical, T.Space.s2)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            .onAppear { toEnd(proxy) }
            .onChange(of: store.s.chat.count) { _, _ in toEnd(proxy) }
            .onChange(of: busy) { _, _ in toEnd(proxy) }
        }
    }

    @MainActor
    private func toEnd(_ proxy: ScrollViewProxy) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(T.Motion.pressDuration))
            withAnimation(Motion.transition) {
                proxy.scrollTo(CHAT_END, anchor: .bottom)
            }
        }
    }

    /// 提示句：可以復原時最前面多一顆「復原上一步」
    private var hintRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: T.Space.s2) {
                if store.canUndo {
                    Chip("復原上一步", selected: true) {
                        store.undo()
                        store.mutate { (d: inout AppState) -> Void in
                            d.chat.append(ChatMsg(r: .sys, t: "復原了上一步。"))
                        }
                    }
                    .accessibilityIdentifier("chat-undo")
                }
                ForEach(Array(hints.enumerated()), id: \.offset) { index, h in
                    Chip(h, disabled: busy) { send(h) }
                        .accessibilityIdentifier("chat-hint-\(index)")
                }
            }
        }
    }

    private var inputRow: some View {
        HStack(spacing: T.Space.s2) {
            TextField("", text: $text, prompt: Text("跟我說要怎麼改").foregroundStyle(C.textSecondary))
                .font(T.TypeScale.body.font)
                .foregroundStyle(C.textPrimary)
                .tint(C.accent)
                .submitLabel(.send)
                .onSubmit { send(text) }
                .onChange(of: text) { _, new in
                    if new.count > CHAT_MAX { text = String(new.prefix(CHAT_MAX)) }
                }
                .padding(.horizontal, T.Space.s4)
                .frame(maxWidth: .infinity, minHeight: T.Size.field)
                .background(C.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(C.fieldBorder, lineWidth: T.Size.hairline))
                .accessibilityLabel("跟我說要怎麼改")
                .accessibilityIdentifier("chat-input")
            sendButton
        }
    }

    private var sendButton: some View {
        let on: Bool = canSend
        return Button {
            send(text)
        } label: {
            LineIcon(IconPaths.send, color: on ? C.onAccent : C.textDisabled)
                .frame(width: T.Size.field, height: T.Size.field)
                .background(on ? C.accent : C.surfaceMuted, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!on)
        .accessibilityLabel("送出")
        .accessibilityIdentifier("chat-send")
    }

    /// 送出一句。先記下我說的，再問（AI 或本機指令），最後把改動套上去
    @MainActor
    private func send(_ raw: String) {
        let msg: String = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if msg.isEmpty || busy { return }
        guard let trip = store.s.trip else { return }
        // TS 送去 AI 的是按下去那一刻的狀態：對話還不含這一句（這一句在提示詞裡另外寫）
        let settings: Settings = store.s.settings
        let chat: [ChatMsg] = store.s.chat
        let useRemote: Bool = remote
        // 按下去那一刻的「現在」：旅途中第幾天幾點。AI 和套用改動都用同一個，免得送出到回來之間跨過時段
        let clock: ChatClock? = store.phase.map { (p: Phase) -> ChatClock in chatClock(p) }
        busy = true
        text = ""
        store.mutate { (d: inout AppState) -> Void in
            d.chat.append(ChatMsg(r: .me, t: msg))
        }
        Task { @MainActor in
            let got: (out: BrainOut, failed: Bool) = await ask(msg, trip, settings, chat, useRemote, clock)
            apply(got.out, got.failed, tripNow(clock))
            busy = false
        }
    }

    /// 兩條路：有接 AI 就問後端，沒回好就退回本機指令；沒接就直接本機指令
    @MainActor
    private func ask(
        _ msg: String, _ trip: Trip, _ settings: Settings, _ chat: [ChatMsg], _ useRemote: Bool, _ clock: ChatClock?
    ) async -> (out: BrainOut, failed: Bool) {
        let now: TripNow? = tripNow(clock)
        if !useRemote {
            return (out: localBrain(msg, trip, now), failed: false)
        }
        do {
            let prompt: String = aiPrompt(msg, trip, settings, chat, clock)
            let out: BrainOut = try await askRemote(prompt, AI_ENDPOINT)
            return (out: out, failed: false)
        } catch {
            return (out: localBrain(msg, trip, now), failed: true)
        }
    }

    /// 把回來的動作套到行程上，對話裡記下改了什麼、哪幾步沒做成。有改到行程才留復原
    @MainActor
    private func apply(_ out: BrainOut, _ failed: Bool, _ now: TripNow?) {
        if failed { Haptic.notify(.error) }
        // 旅途中不整趟重排：去過的站會被洗掉
        let blockRegen: Bool = out.regen == true && now != nil
        let regen: Bool = out.regen == true && !blockRegen
        let willChange: Bool = regen || !out.ops.isEmpty
        store.act(undoable: willChange) { (d: inout AppState) -> String? in
            guard var trip = d.trip else { return nil }
            if failed {
                d.chat.append(ChatMsg(r: .sys, t: "AI 這次沒回好，先用內建的簡單指令。"))
            }
            var changes: [String] = []
            if regen {
                let own: (flight: Double, spend: [Spend]?, rate: Double?) = ownOf(trip)
                var fresh: Trip = generate(draftOf(trip), d.settings, true)
                fresh.flight = own.flight
                fresh.spend = own.spend
                fresh.rate = own.rate
                trip = fresh
                d.settingsDirty = false
                changes.append("整趟照現在的設定重排了")
            }
            var seeds: [Seed] = d.seeds
            let r: (changes: [String], notes: [String]) = applyOps(&trip, &seeds, out.ops, now)
            d.trip = trip
            d.seeds = seeds
            changes.append(contentsOf: r.changes)
            d.chat.append(ChatMsg(r: .ai, t: out.reply, changes: changes))
            if blockRegen {
                d.chat.append(ChatMsg(r: .sys, t: NO_REGEN_ON_TRIP))
            }
            let notes: [String] = r.notes + warnings(trip)
            for n in notes {
                d.chat.append(ChatMsg(r: .sys, t: n))
            }
            if hasAiPlace(out.ops) {
                d.chat.append(ChatMsg(r: .sys, t: "AI 自己加的地點還沒核對過，去之前查一下。"))
            }
            d.chat = Array(d.chat.suffix(CHAT_KEEP))
            return nil
        }
    }
}
