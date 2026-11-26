// 畫面外框：分頁的外框（Screen）、彈出卡的外框（SheetScaffold）、懸浮分頁列、提示條。
// 對應 mobile 的 components/Screen.tsx、components/Sheet.tsx、DomyTabBar、components/NoticeBar.tsx。
import Accessibility
import Observation
import SwiftUI
import UIKit

/// 有懸浮分頁列的畫面，捲動內容底部要留這麼多空間（安全區另外算，SwiftUI 會自己加）
let tabBarClearance: CGFloat = T.Size.tabBarBottom + T.Size.tabBar + T.Space.s4

/// 分頁的外框：畫布色、左右 20 邊距、大標題、區塊之間間距 s6。
/// actions 是大標題上面靠右那一排圓鈕（分頁最上層的更多、平常的我）；推進頁不給。
/// 鍵盤出來時 SwiftUI 會自己把正在打的那一格推上來。
/// 要捲到某一塊：在那一塊加 `.id("名字")`，外面包 ScrollViewReader 傳 proxy 進來用，或用 `scrollTo` 參數。
struct Screen<Actions: View, Content: View>: View {
    let title: String
    /// 設了就捲到那個 id（操作說明用）。捲完自己不會清掉，要呼叫的人清
    var scrollTo: String?
    /// 捲動的階段變了就叫（手指在捲、放開後還在滑、停了、程式在捲）。沒給就不管。
    /// 這趟分頁用它分辨是手指捲的還是點分頁程式捲的，手指捲到哪一天，天數分頁才跟著換
    var onScrollPhase: ((ScrollPhase) -> Void)?
    @ViewBuilder var actions: Actions
    @ViewBuilder var content: Content

    init(
        _ title: String, scrollTo: String? = nil, onScrollPhase: ((ScrollPhase) -> Void)? = nil,
        @ViewBuilder actions: () -> Actions,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.scrollTo = scrollTo
        self.onScrollPhase = onScrollPhase
        self.actions = actions()
        self.content = content()
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: T.Space.s6) {
                    VStack(alignment: .leading, spacing: T.Space.s1) {
                        if Actions.self != EmptyView.self {
                            actions
                        }
                        DomyText(title, .largeTitle)
                            .accessibilityAddTraits(.isHeader)
                    }
                    content
                }
                .padding(.top, T.Space.s2)
                .padding(.horizontal, T.Size.screenMargin)
                .padding(.bottom, tabBarClearance)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            .onScrollPhaseChange { (_: ScrollPhase, now: ScrollPhase) in
                if let onScrollPhase {
                    onScrollPhase(now)
                }
            }
            .background(C.canvas.ignoresSafeArea())
            .safeAreaInset(edge: .top, spacing: 0) { statusCover }
            .onChange(of: scrollTo) { _, target in
                guard let target else { return }
                withAnimation(Motion.transition) {
                    proxy.scrollTo(target, anchor: .center)
                }
            }
        }
    }

    /// 往下捲的時候，內容不要跑到狀態列底下跟時間疊在一起。自己不佔高度，只把底色往上鋪滿安全區。
    /// 只有分頁最上層（有右上角那排）要；推進頁的導覽列自己有底色
    @ViewBuilder private var statusCover: some View {
        if Actions.self != EmptyView.self {
            Color.clear
                .frame(height: 0)
                .frame(maxWidth: .infinity)
                .background(C.canvas, ignoresSafeAreaEdges: .top)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

extension Screen where Actions == EmptyView {
    init(_ title: String, scrollTo: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title, scrollTo: scrollTo, actions: { EmptyView() }, content: content)
    }
}

/// 不整頁捲動的分頁外框：大標題和右上角固定在上面，內容自己管捲動（問 AI 的對話）。
/// 底部留分頁列的空間
struct FixedScreen<Actions: View, Content: View>: View {
    let title: String
    @ViewBuilder var actions: Actions
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder actions: () -> Actions, @ViewBuilder content: () -> Content) {
        self.title = title
        self.actions = actions()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: T.Space.s3) {
            VStack(alignment: .leading, spacing: T.Space.s1) {
                actions
                DomyText(title, .largeTitle)
                    .accessibilityAddTraits(.isHeader)
            }
            content
        }
        .padding(.top, T.Space.s2)
        .padding(.horizontal, T.Size.screenMargin)
        .padding(.bottom, tabBarClearance)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(C.canvas.ignoresSafeArea())
    }
}

/// 彈出卡的外框：系統的頁面卡片，可以往下拉關掉；右上角一直有「關閉」。
/// 用在 `.sheet` 裡面。scroll 為 false 時內容自己管捲動（例如對話、地圖）。
/// 開著的時候有提示條，就在這張裡面的下緣出現（SheetNotice），內容讓出位置，不會被蓋住；
/// 外面自己用 safeAreaInset 釘了下緣按鈕的（MapSheet），提示條在按鈕上面。
struct SheetScaffold<Content: View>: View {
    let title: String
    var scroll: Bool = true
    let onClose: () -> Void
    @ViewBuilder var content: Content

    init(_ title: String, scroll: Bool = true, onClose: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.title = title
        self.scroll = scroll
        self.onClose = onClose
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: T.Space.s3) {
                DomyText(title, .title2, lines: 2)
                    .fillLeading()
                    .accessibilityAddTraits(.isHeader)
                DomyIconButton(title: "關閉", label: "關閉", neutral: true, action: onClose)
            }
            .padding(.horizontal, T.Size.screenMargin)
            .padding(.top, T.Space.s5)
            .padding(.bottom, T.Space.s3)
            if scroll {
                ScrollView {
                    VStack(alignment: .leading, spacing: T.Space.s4) {
                        content
                    }
                    .padding(.horizontal, T.Size.screenMargin)
                    .padding(.bottom, T.Space.s6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollDismissesKeyboard(.interactively)
            } else {
                VStack(alignment: .leading, spacing: T.Space.s3) {
                    content
                }
                .padding(.horizontal, T.Size.screenMargin)
                .padding(.bottom, T.Space.s6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SheetNotice()
        }
        .background(C.canvas.ignoresSafeArea())
    }
}

/// 分頁列的一個分頁。icon 是 SVG path
struct TabItem: Identifiable {
    let id: String
    let title: String
    let icon: String
}

/// 懸浮膠囊分頁列，最多 4 個分頁
struct DomyTabBar: View {
    let tabs: [TabItem]
    let selected: String
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: T.Space.s1) {
            ForEach(tabs) { tab in
                let focused: Bool = tab.id == selected
                let color: Color = focused ? C.strong : C.textPrimary
                Button {
                    // 點的是現在這格也要傳出去：推進到裡面的頁面時，再點一次回最上層
                    if !focused {
                        Haptic.select()
                    }
                    onSelect(tab.id)
                } label: {
                    VStack(spacing: T.Space.s1 / 2) {
                        LineIcon(tab.icon, color: color)
                        Text(tab.title)
                            .font(T.TypeScale.caption.font.weight(focused ? .semibold : .medium))
                            .foregroundStyle(color)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(focused ? C.soft : Color.clear, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(tab.title)
                .accessibilityIdentifier("tab-\(tab.id)")
                .accessibilityAddTraits(focused ? [.isButton, .isSelected] : [.isButton])
            }
        }
        .padding(T.Space.s1 + T.Space.s1 / 2)
        .frame(maxWidth: T.Size.tabBarWidth)
        .frame(height: T.Size.tabBar)
        .background(C.surface, in: Capsule())
        .domyElevation(T.Elevation.level2)
        .padding(.bottom, T.Size.tabBarBottom)
    }
}

/// 懸浮分頁列從安全區下緣算起佔的高度，加上它跟上面那一列的間隔
let tabBarRoom: CGFloat = T.Size.tabBarBottom + T.Size.tabBar + T.Space.s3

/// 鍵盤有沒有蓋到懸浮分頁列。分頁列、講的那一列、提示條都看這一份，不會一個收了一個沒收。
/// 外殼（RadishApp.swift 的 ShellTabBar）聽系統通知來改
@MainActor
@Observable
final class KeyboardStage {
    static let shared: KeyboardStage = KeyboardStage()
    private(set) var up: Bool = false

    private init() {}

    /// 接實體鍵盤時只有一條或在畫面外，不會蓋到分頁列，就照沒有鍵盤排
    func willShow(_ note: Notification) {
        guard let end = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let shown: CGFloat = UIScreen.main.bounds.height - end.minY
        change(shown > tabBarRoom)
    }

    func willHide() {
        change(false)
    }

    private func change(_ now: Bool) {
        if up == now { return }
        withAnimation(Motion.transition) {
            up = now
        }
    }
}

/// 問 AI 分頁最下面講的那一列（Components/TalkBar.swift）大約多高：說法一排加輸入框。提示條要浮在它上面
let talkBarClearance: CGFloat = T.Size.touch + T.Size.field + T.Space.s4

/// 半頁開著多久還沒關，提示條才在半頁裡出現。做完就自己收起來的半頁不會閃一下
private let sheetNoticeDelay: Double = 0.8  // 等半頁收掉的時間，不是動畫

/// 現在是哪一則提示由半頁顯示。外殼看到是同一則就不畫，不會兩條一起看得到
@MainActor
@Observable
final class NoticeStage {
    static let shared: NoticeStage = NoticeStage()
    /// Notice.id。nil 是沒有半頁在顯示
    var inSheet: Int?

    private init() {}
}

/// 提示條的樣子，外殼和半頁共用
private struct NoticeCard: View {
    let notice: Notice
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: T.Space.s3) {
            DomyText(notice.text, .subheadline, color: C.surface)
            if notice.canUndo {
                Button {
                    onUndo()
                } label: {
                    DomyText("復原", .callout, color: C.bright)
                        .frame(minWidth: T.Size.touch, minHeight: T.Size.touch)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("notice-undo")
            }
        }
        .padding(.vertical, notice.canUndo ? 0 : T.Space.s3)
        .padding(.horizontal, T.Space.s4)
        .background(C.textPrimary, in: RoundedRectangle(cornerRadius: T.Radius.lg, style: .continuous))
        .domyElevation(T.Elevation.level2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("notice-bar")
    }
}

/// 提示條：做完一個動作後告訴你發生了什麼，可以復原的會帶一顆「復原」。浮在分頁列和講的那一列上方。
/// 一直掛在外殼上：不管提示條畫在哪裡，VoiceOver 都由這裡念一次
struct NoticeBar: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ZStack(alignment: .bottom) {
            if let notice = store.notice, NoticeStage.shared.inSheet != notice.id {
                NoticeCard(notice: notice) {
                    store.dismissNotice()
                    store.undo()
                }
                .padding(.horizontal, T.Size.screenMargin)
                .padding(.bottom, (KeyboardStage.shared.up ? T.Space.s4 : tabBarClearance) + talkBarClearance)
                .transition(.opacity)
            }
        }
        .onChange(of: store.notice?.id, initial: true) { (_: Int?, now: Int?) in
            if now != nil {
                announce()
            }
        }
    }

    /// 用高優先：按完按鈕焦點會跳走，一般優先的會被蓋掉
    private func announce() {
        guard let notice = store.notice else { return }
        var words: AttributedString = AttributedString(notice.canUndo ? notice.text + "可以復原。" : notice.text)
        words.accessibilitySpeechAnnouncementPriority = .high
        AccessibilityNotification.Announcement(words).post()
    }
}

/// 半頁裡面的提示條，放在 SheetScaffold 下緣。拿不到 AppStore 就不出現
private struct SheetNotice: View {
    @Environment(AppStore.self) private var store: AppStore?
    /// 這張半頁接手顯示的那一則
    @State private var shown: Int?

    var body: some View {
        VStack(spacing: 0) {
            if let store, let notice = store.notice, notice.id == shown {
                NoticeCard(notice: notice) {
                    store.dismissNotice()
                    store.undo()
                }
                .padding(.horizontal, T.Size.screenMargin)
                .padding(.vertical, T.Space.s3)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .task(id: store?.notice?.id) {
            await takeOver()
        }
        .onDisappear {
            // 半頁收掉了，還沒過時的那一則還給外殼
            NoticeStage.shared.inSheet = nil
        }
    }

    private func takeOver() async {
        guard let id = store?.notice?.id else { return }
        try? await Task.sleep(for: .seconds(sheetNoticeDelay))
        if Task.isCancelled { return }
        withAnimation(Motion.transition) {
            shown = id
            NoticeStage.shared.inSheet = id
        }
    }
}
