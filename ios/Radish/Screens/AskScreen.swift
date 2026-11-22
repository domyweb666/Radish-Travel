// 「問 AI」分頁（S04，線框 A14）：這趟的整段對話，最新的在最下面。
// 最上面一行「在看：第 3 天・12/18（五）」點了換天（只影響下一句），旁邊「看這一天」切到這趟分頁那一天。
// 手機答的那則標「手機算的，沒有問 AI」。輸入列在最下面、分頁列上面，跟這一天最下面那一列是同一串對話。
// 原本是從這趟打開的彈出卡（mobile/src/sheets/ChatSheet.tsx），片 3 搬成分頁；一則一則的樣子在 Sheets/ReplySheet.swift。
// AI 端點：AI_ENDPOINT（Chat.swift）在 app 啟動時從 Info.plist 讀進來，已經是完整網址。
import SwiftUI

/// 捲到底用的記號
private let ASK_END: String = "ask-end"

struct AskScreen: View {
    @Environment(AppStore.self) private var store
    @Environment(Nav.self) private var nav

    init() {}

    /// 在看第幾天：跟著這趟分頁最後看的那一天；還沒換過天就是今天（旅途中）或第 1 天
    private func askDay(_ trip: Trip) -> Int {
        var today: Int? = nil
        if case .trip(let d)? = store.phase { today = d }
        return max(1, min(nav.tripDay ?? today ?? 1, trip.days))
    }

    /// 上面那排說法（線框 A14）。沒接 AI 的時候換成本機指令聽得懂的
    private var hints: [String] {
        if store.aiOn { return ["上午下午對調", "多排一間咖啡廳", "有哪些要先訂"] }
        return ["這趟想輕鬆一點", "上午下午對調", "有哪些要先訂"]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: T.Space.s3) {
            VStack(alignment: .leading, spacing: T.Space.s1) {
                TopActions()
                DomyText("問 AI", .largeTitle)
                    .accessibilityAddTraits(.isHeader)
            }
            .padding(.horizontal, T.Size.screenMargin)
            if let trip = store.s.trip {
                looking(trip)
                    .padding(.horizontal, T.Size.screenMargin)
                talk(trip)
            } else {
                empty
            }
        }
        .padding(.top, T.Space.s2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(C.canvas.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let trip = store.s.trip {
                let day: Int = askDay(trip)
                TalkBar(label: "第 \(day) 天", target: .day(day), ids: "chat", hints: hints) {}
            }
        }
    }

    private var empty: some View {
        DomyEmptyState(
            icon: IconPaths.tabAsk,
            title: "還沒有這趟",
            message: "先在「這趟」排好一趟，再來這裡跟 AI 講要怎麼改。",
            actionTitle: "去排一趟",
            action: { nav.show(.trip) }
        )
        .padding(.horizontal, T.Size.screenMargin)
        .padding(.bottom, tabBarClearance)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 在看：第 N 天・日期（點了換天）、看這一天
    private func looking(_ trip: Trip) -> some View {
        let day: Int = askDay(trip)
        let days: [Int] = trip.days >= 1 ? Array(1...trip.days) : []
        return HStack(spacing: T.Space.s2) {
            Menu {
                ForEach(days, id: \.self) { (d: Int) in
                    Button("第 \(d) 天・\(tripDayLabel(trip, d))") {
                        Haptic.select()
                        nav.tripDay = d
                    }
                }
            } label: {
                HStack(spacing: T.Space.s1) {
                    DomyText("在看：第 \(day) 天・\(tripDayLabel(trip, day))", .subheadline, weight: .semibold, lines: 1)
                    Image(systemName: "chevron.down")
                        .font(T.TypeScale.footnote.font.weight(.semibold))
                        .foregroundStyle(C.textSecondary)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: T.Size.touch)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("在看第 \(day) 天，點了換天")
            .accessibilityIdentifier("ask-day")
            Spacer(minLength: 0)
            DomyButton("看這一天", variant: .secondary, size: .compact) {
                nav.tripDay = day
                nav.show(.trip)
            }
            .accessibilityIdentifier("ask-see-day")
        }
    }

    /// 中間的對話。有新的一則、或開始等回覆時捲到底
    private func talk(_ trip: Trip) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: T.Space.s2) {
                    intro
                    ForEach(Array(store.s.chat.enumerated()), id: \.offset) { index, m in
                        line(index, m)
                    }
                    if store.talkBusy {
                        TalkNote(text: "想一下…")
                    }
                    if case .consent(let text, _) = store.talkStage {
                        Card {
                            TalkConsent(text: text) {}
                        }
                    }
                    Color.clear.frame(height: 0).id(ASK_END)
                }
                .padding(.horizontal, T.Size.screenMargin)
                .padding(.vertical, T.Space.s2)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            .frame(maxHeight: .infinity)
            .onAppear { toEnd(proxy) }
            .onChange(of: store.s.chat.count) { _, _ in toEnd(proxy) }
            .onChange(of: store.talkStage) { _, _ in toEnd(proxy) }
        }
    }

    /// 最上面一行小字：講什麼都可以；還沒接 AI 時老實說只聽得懂幾種說法
    private var intro: some View {
        let remote: String = "想改、想問，直接講。改完會列出動了哪幾站，可以復原。AI 不知道即時的營業時間和票價，去之前查一下。"
        let local: String = "這一版還沒接上 AI，只聽得懂幾種說法，例如「第 3 天上午下午對調」「不要樂天世界」「這趟想輕鬆一點」。到右上角「平常的我」填 Claude API 金鑰，就能直接問 AI。"
        return TalkNote(text: store.aiOn ? remote : local)
    }

    @ViewBuilder private func line(_ index: Int, _ m: ChatMsg) -> some View {
        switch m.r {
        case .me:
            mine(index, m)
        case .ai:
            TalkAnswer(index: index, m: m, inline: true, seeDay: { (d: Int) in
                nav.tripDay = d
                nav.show(.trip)
            })
        case .sys:
            TalkNote(text: m.t)
        }
    }

    /// 我說的那句。沒收到回覆的，最後一句可以再送一次
    @ViewBuilder private func mine(_ index: Int, _ m: ChatMsg) -> some View {
        TalkMine(text: m.t)
        if m.failed != nil {
            VStack(alignment: .trailing, spacing: T.Space.s1) {
                DomyText("這句沒有收到回覆，這趟沒有動。", .footnote, tone: .secondary, align: .trailing)
                if index == store.lastTalk {
                    DomyButton("再送一次", variant: .secondary, size: .compact, disabled: store.talkBusy) {
                        store.retryTalk(index)
                    }
                    .accessibilityIdentifier("chat-retry")
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    @MainActor
    private func toEnd(_ proxy: ScrollViewProxy) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(T.Motion.pressDuration))
            withAnimation(Motion.transition) {
                proxy.scrollTo(ASK_END, anchor: .bottom)
            }
        }
    }
}
