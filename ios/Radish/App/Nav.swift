// 分頁和推進頁的總管：現在在哪個分頁、每個分頁推進到哪幾頁、這趟分頁在看哪一天。
// 畫面要推進一頁只說 `nav.push(.check)`，推進到現在這個分頁的堆疊裡。
// 用法：`@Environment(Nav.self) private var nav`。
import Observation
import SwiftUI

/// 分頁列的三格：這趟／問 AI／旅行（.uiux/02-流程-暫定.md 5-4）
enum TabKey: String, CaseIterable {
    case trip, ask, trips
}

/// 推進頁。從哪個分頁按的，就推進那個分頁
enum Push: Hashable {
    /// 檢查這趟：原本行前的出發前
    case check
    /// 須知：在當地、按天、回程
    case notes
    /// 花費：從更多進來，旅途中也從下一站卡下面進來
    case cost
    /// 代購：別人託這趟幫買的。從這趟標題下面的常駐入口進來（總覽頁做好之後收進總覽）
    case errands
    /// 平常的我：右上角進來
    case me
    /// 一站（S06，線框 A5）：從這一天的清單、下一站卡、須知、檢查這趟、去過的那一趟進來
    case stop(id: String)
    /// 去過的那一趟（S20，線框 A16）：現在這趟，或某一趟已經收起來的
    case visited(AlbumSource)
}

/// 跟 AI 講的那一列在看哪裡（輸入列左邊的小標）。這一天的最下面是 .day，一站的最下面是 .stop
enum TalkTarget: Hashable {
    case day(Int)
    case stop(id: String)
}

@MainActor
@Observable
final class Nav {
    var tab: TabKey = .trip
    var trip: [Push] = []
    var ask: [Push] = []
    var trips: [Push] = []
    /// 這趟分頁在看第幾天。放在這裡，切到別的分頁再切回來還是同一天。nil 是跟著今天或第 1 天。
    /// 換了一趟、跨了一天由外殼的 DayWatch（RadishApp.swift）重設
    var tripDay: Int?

    /// 推進一頁到現在這個分頁。最上面已經是這一頁就不再推一次（連按兩下）
    func push(_ page: Push) {
        switch tab {
        case .trip:
            if trip.last != page { trip.append(page) }
        case .ask:
            if ask.last != page { ask.append(page) }
        case .trips:
            if trips.last != page { trips.append(page) }
        }
    }

    /// 點分頁列：換到那個分頁；點的就是現在這個分頁，回到最上層
    func select(_ next: TabKey) {
        if next == tab {
            popToRoot(next)
        } else {
            tab = next
        }
    }

    /// 從別的分頁跳到某個分頁的最上層（例：旅行分頁按了切到這一趟）
    func show(_ next: TabKey) {
        popToRoot(next)
        tab = next
    }

    private func popToRoot(_ key: TabKey) {
        switch key {
        case .trip: trip = []
        case .ask: ask = []
        case .trips: trips = []
        }
    }
}

extension View {
    /// 每個分頁最上層用的：系統導覽列藏起來（標題和右上角自己畫），推進的頁面從這裡接
    func pushPages(_ backTitle: String) -> some View {
        self
            .navigationTitle(backTitle)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Push.self) { (page: Push) in
                PushPage(page: page)
            }
    }
}

/// 推進進來的那一頁。導覽列只放系統的返回，返回寫的是上一層的標題（例：首爾 5 天）；大標題在頁面裡
struct PushPage: View {
    let page: Push

    var body: some View {
        Group {
            switch page {
            case .check:
                CheckScreen()
            case .notes:
                NotesScreen()
            case .cost:
                CostScreen()
            case .errands:
                ErrandsScreen()
            case .me:
                MeScreen()
            case .stop(let id):
                StopScreen(id: id)
            case .visited(let source):
                VisitedScreen(source: source)
            }
        }
        .toolbarBackground(C.canvas, for: .navigationBar)
    }
}

/// 分頁右上角那幾顆圓鈕：更多（只有這趟有）、平常的我
struct TopActions: View {
    @Environment(Nav.self) private var nav
    var more: (() -> Void)?

    init(more: (() -> Void)? = nil) {
        self.more = more
    }

    var body: some View {
        HStack(spacing: T.Space.s2) {
            Spacer(minLength: 0)
            if let more {
                DomyIconButton(icon: IconPaths.more, label: "更多", neutral: true, action: more)
                    .accessibilityIdentifier("open-more")
            }
            DomyIconButton(icon: IconPaths.tabMe, label: "平常的我", neutral: true) {
                nav.push(.me)
            }
            .accessibilityIdentifier("open-me")
        }
    }
}
