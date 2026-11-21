// 蘿蔔旅行：四個分頁（行前／這趟／旅行／我），懸浮分頁列。打開時先停在「這趟」。
// 對應 mobile/App.tsx。
import SwiftUI

@main
struct RadishApp: App {
    @State private var store: AppStore
    @State private var sheets = Sheets()
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
        _store = State(initialValue: AppStore())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(sheets)
                .tint(C.accent)
                .task { store.load() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        store.refreshToday()
                    }
                }
        }
    }
}

enum TabKey: String, CaseIterable {
    case prep, trip, trips, me
}

/// 「行前」頁的四段：出發前、在當地、回來後、花費
enum PrepStage: String, CaseIterable, Hashable {
    case before, there, back, cost
}

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(Sheets.self) private var sheets
    @State private var tab: TabKey = .trip
    /// 從「這趟」的提醒跳到「行前」時，指定要開哪一段。自己點分頁列就照旅程走到哪決定
    @State private var prepOpen: PrepStage?

    private let tabs: [TabItem] = [
        TabItem(id: TabKey.prep.rawValue, title: "行前", icon: IconPaths.tabPrep),
        TabItem(id: TabKey.trip.rawValue, title: "這趟", icon: IconPaths.tabTrip),
        TabItem(id: TabKey.trips.rawValue, title: "旅行", icon: IconPaths.tabTrips),
        TabItem(id: TabKey.me.rawValue, title: "我", icon: IconPaths.tabMe),
    ]

    /// 行程、打勾、提醒開關有變，就把排好的通知整批換新。關掉提醒時是清空
    private var reminders: [Reminder] {
        store.s.remind ? remindersOf(store.s, store.today) : []
    }

    /// 通知內容有沒有變，用這串字比
    private var reminderKey: String {
        let lines: [String] = reminders.map { item in "\(item.on)|\(item.title)|\(item.body)" }
        return (store.ready ? "1" : "0") + lines.joined(separator: "/")
    }

    var body: some View {
        @Bindable var sheets = sheets
        ZStack(alignment: .bottom) {
            C.canvas.ignoresSafeArea()
            if store.ready {
                Group {
                    switch tab {
                    case .trip:
                        TripScreen(
                            goSettings: { tab = .me },
                            goPrep: { stage in
                                prepOpen = stage
                                tab = .prep
                            })
                    case .prep:
                        PrepScreen(open: prepOpen, goTrip: { tab = .trip })
                    case .trips:
                        TripsScreen(goTrip: { tab = .trip })
                    case .me:
                        MeScreen()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                NoticeBar()
                DomyTabBar(tabs: tabs, selected: tab.rawValue) { key in
                    prepOpen = nil
                    tab = TabKey(rawValue: key) ?? .trip
                }
                .ignoresSafeArea(.keyboard, edges: .bottom)
            }
        }
        .sheet(item: $sheets.req) { req in
            SheetRouter(req: req)
                .environment(store)
                .environment(sheets)
                .tint(C.accent)
        }
        .onChange(of: reminderKey, initial: true) { _, _ in
            guard store.ready else { return }
            let list: [Reminder] = reminders
            Task { await syncReminders(list) }
        }
    }
}
