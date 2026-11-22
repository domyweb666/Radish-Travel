// 蘿蔔旅行：三個分頁（這趟／問 AI／旅行），懸浮分頁列。打開時先停在「這趟」。
// 平常的我從右上角推進；原本的行前拆成檢查這趟、須知、花費三個推進頁（Nav.swift）。
import SwiftUI

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
        CLAUDE_KEY = args.contains("-uitest-reset") ? "" : ClaudeKeyStore.load()
        _store = State(initialValue: AppStore())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(sheets)
                .environment(nav)
                .tint(C.accent)
                .task { store.load() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        store.refreshToday()
                    } else {
                        // 要離開前景（進多工畫面、回主畫面）：排著還沒寫的那一份現在就寫，被滑掉也不會掉
                        store.flush(wait: true)
                    }
                }
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
