// 畫面外框：分頁的外框（Screen）、彈出卡的外框（SheetScaffold）、懸浮分頁列、提示條。
// 對應 mobile 的 components/Screen.tsx、components/Sheet.tsx、DomyTabBar、components/NoticeBar.tsx。
import SwiftUI

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
    @ViewBuilder var actions: Actions
    @ViewBuilder var content: Content

    init(
        _ title: String, scrollTo: String? = nil, @ViewBuilder actions: () -> Actions,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.scrollTo = scrollTo
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
            .background(C.canvas.ignoresSafeArea())
            .onChange(of: scrollTo) { _, target in
                guard let target else { return }
                withAnimation(Motion.transition) {
                    proxy.scrollTo(target, anchor: .center)
                }
            }
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

/// 提示條：做完一個動作後告訴你發生了什麼，可以復原的會帶一顆「復原」。浮在分頁列上方。
struct NoticeBar: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        if let notice = store.notice {
            HStack(spacing: T.Space.s3) {
                DomyText(notice.text, .subheadline, color: C.surface)
                if notice.canUndo {
                    Button {
                        store.dismissNotice()
                        store.undo()
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
            .padding(.horizontal, T.Size.screenMargin)
            .padding(.bottom, tabBarClearance)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("notice-bar")
            .transition(.opacity)
        }
    }
}
