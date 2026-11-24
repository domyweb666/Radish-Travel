// 蘿蔔旅行：三個分頁（這趟／問 AI／旅行），懸浮分頁列。打開時先停在「這趟」。
// 平常的我從右上角推進；原本的行前拆成檢查這趟、須知、花費三個推進頁（Nav.swift）。
import Combine
import SwiftUI
import UIKit

@main
struct RadishApp: App {
    @State private var store: AppStore
    @State private var sheets = Sheets()
    @State private var nav = Nav()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let args: [String] = ProcessInfo.processInfo.arguments
        // UI 測試用：從空白開始。平常不會帶這個參數
        if args.contains("-uitest-reset") {
            try? FileManager.default.removeItem(at: AppStore.defaultURL())
        }
        if let endpoint = Bundle.main.object(forInfoDictionaryKey: "RadishAIEndpoint") as? String {
            AI_ENDPOINT = endpoint
        }
        // 平常的我裡填的 Claude API 金鑰（存在鑰匙圈）。UI 測試從空白開始，不讀
        CLAUDE_KEY = args.contains("-uitest-reset") ? "" : SecretStore.load(.claudeKey)
        BRIDGE_URL = args.contains("-uitest-reset") ? "" : SecretStore.load(.bridge)
        #if DEBUG
            // UI 測試用的場景和假的 AI（UITestScenes.swift）。要在 AppStore 建起來之前
            UITestScenes.prepare(args)
        #endif
        _store = State(initialValue: AppStore())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(sheets)
                .environment(nav)
                .tint(C.accent)
                .task {
                    // 只有剛開 app 那一次：讀完檔，再刪以前拿掉的照片。之後復原紀錄可能還用得到，不能刪
                    if !store.ready {
                        store.load()
                        PhotoStore.sweepRemoved(store.s, file: AppStore.defaultURL())
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        store.refreshToday()
                        // 上次沒寫成功的，回來再寫一次。都寫好了就不做事
                        store.flush()
                    } else {
                        // 要離開前景（進多工畫面、回主畫面）：排著還沒寫的那一份現在就寫，被滑掉也不會掉
                        store.flush(wait: true)
                    }
                }
        }
    }
}

/// 盯著換了一趟、跨了一天：這趟分頁看的那一天跟著換。放在外殼，不在這趟分頁的時候也要跟
private struct DayWatch: View {
    @Environment(AppStore.self) private var store
    @Environment(Nav.self) private var nav

    /// 旅途中的今天是第幾天。不在旅途中就是 nil
    private var today: Int? {
        if case .trip(let d)? = store.phase { return d }
        return nil
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: store.s.trip?.id) { (_: String?, _: String?) in
                // 換了一趟：旅途中跳到今天，其他從第 1 天看起
                nav.tripDay = today
            }
            .onChange(of: today) { (_: Int?, now: Int?) in
                if let now {
                    nav.tripDay = now
                }
            }
            // app 一直開著跨過午夜
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { (_: Notification) in
                store.refreshToday()
            }
    }
}

/// 外殼只看 store.ready，不讀行程資料：改一站的時候外殼不用跟著重算。通知的重排在 AppStore 存檔時做
struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(Sheets.self) private var sheets
    @Environment(Nav.self) private var nav

    private let tabs: [TabItem] = [
        TabItem(id: TabKey.trip.rawValue, title: "這趟", icon: IconPaths.tabTrip),
        TabItem(id: TabKey.ask.rawValue, title: "問 AI", icon: IconPaths.tabAsk),
        TabItem(id: TabKey.trips.rawValue, title: "旅行", icon: IconPaths.tabTrips),
    ]

    var body: some View {
        @Bindable var sheets = sheets
        @Bindable var nav = nav
        ZStack(alignment: .bottom) {
            C.canvas.ignoresSafeArea()
            if store.ready {
                Group {
                    switch nav.tab {
                    case .trip:
                        NavigationStack(path: $nav.trip) {
                            TripScreen()
                        }
                    case .ask:
                        NavigationStack(path: $nav.ask) {
                            AskScreen()
                                .pushPages("問 AI")
                        }
                    case .trips:
                        NavigationStack(path: $nav.trips) {
                            TripsScreen(goTrip: { nav.show(.trip) })
                                .pushPages("旅行")
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                DayWatch()
                NoticeBar()
                DomyTabBar(tabs: tabs, selected: nav.tab.rawValue) { key in
                    nav.select(TabKey(rawValue: key) ?? .trip)
                }
                .ignoresSafeArea(.keyboard, edges: .bottom)
            }
        }
        .sheet(item: $sheets.req) { req in
            SheetRouter(req: req)
                .environment(store)
                .environment(sheets)
                .environment(nav)
                .tint(C.accent)
        }
    }
}
