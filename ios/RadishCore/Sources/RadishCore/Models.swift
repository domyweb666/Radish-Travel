// 資料型別。照 mobile/src/domain/types.ts 一對一搬過來，欄位名字不改（n、kr、a、s、c…），
// 這樣規則搬過來時可以逐行對照。
// 這個資料夾只准 import Foundation：規則引擎要能在 Linux 上跑測試。
import Foundation

enum Part: String, Codable, CaseIterable, CodingKeyRepresentable, Sendable {
    case am, pm, eve
}

enum Cat: String, Codable, CaseIterable, CodingKeyRepresentable, Sendable {
    case eat, shop, fun, sight, art, nature, cafe, night, kpop
}

enum FoodKind: String, Codable, CaseIterable, CodingKeyRepresentable, Sendable {
    case street, local, famous, fine
}

enum IconKey: String, Codable, CaseIterable, Sendable {
    case eat, shop, fun, sight, art, nature, cafe, night, kpop
    case market, spa, boat, view, pin
}

enum AreaKey: String, Codable, CaseIterable, CodingKeyRepresentable, Sendable {
    case A, B, C, D, E, F, G, H, I, K, J
}

enum BaseKey: String, Codable, CaseIterable, CodingKeyRepresentable, Sendable {
    case C, D, G, I
}

enum Purpose: String, Codable, CaseIterable, CodingKeyRepresentable, Sendable {
    case rest, eat, fun, see
}

/// L 大站、S 小站（TS 的 Size）
enum StopSize: String, Codable, CaseIterable, Sendable {
    case L, S
}

enum StopStatus: String, Codable, Sendable {
    case kept, pulled
}

/// 這趟臨時調整。只改這一趟，不動「我」裡存好的偏好
enum Tweak: String, Codable, CaseIterable, CodingKeyRepresentable, Sendable {
    case elder, easy, save, treat
}

enum Pace: String, Codable, CaseIterable, CodingKeyRepresentable, Sendable {
    case slow, mid, fast
}

enum Walk: String, Codable, CaseIterable, CodingKeyRepresentable, Sendable {
    case less, normal, lots
}

/// 身體上要避開的（TS 的 Body；在 SwiftUI 裡 Body 這個名字有別的意思，所以改名）
enum BodyLimit: String, Codable, CaseIterable, CodingKeyRepresentable, Sendable {
    case stairs, heat, cold
}

enum StayKind: String, Codable, CaseIterable, CodingKeyRepresentable, Sendable {
    case cheap, mid, nice
}

/// 排隊願意度。TS 是 'no' | 'some' | 'any'，some 和 any 在 Swift 是保留字，所以換名字、存的字不變
enum QueueKind: String, Codable, CaseIterable, Sendable {
    case no
    case few = "some"
    case all = "any"
}

enum Wake: String, Codable, CaseIterable, Sendable {
    case early, normal, late
}

enum Move: String, Codable, CaseIterable, Sendable {
    case transit, taxi, walk
}

enum LearnKind: String, Codable, Sendable {
    case place, cat, food
}

enum ChatRole: String, Codable, Sendable {
    case me, ai, sys
}

struct Place: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var n: String  // 中文名
    var kr: String  // 當地文字名
    var a: AreaKey
    var s: StopSize
    var c: Cat
    var lat: Double
    var lng: Double
    var b: Bool?  // 要先訂
    var fee: Double?  // 粗估 NT$
    var tip: String?  // 須知
    var l: Bool?  // 輕鬆
    var up: Bool?  // 坡多或階梯多。粗略標的，沒核對
    var f: FoodKind?
    var ic: IconKey?
}

struct Stop: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var n: String
    var kr: String
    var a: AreaKey?  // 自己加的、AI 加的沒有區域（TS 是空字串）
    var s: StopSize
    var c: Cat
    var lat: Double?
    var lng: Double?
    var b: Bool?
    var fee: Double?
    var tip: String?
    var l: Bool?
    var up: Bool?
    var f: FoodKind?
    var ic: IconKey?
    var status: StopStatus = .kept
    var swaps: Int = 0
    var why: String = ""  // 為什麼排這一站
    var say: String?  // 那一句
    var photos: [String]?  // 去過之後加的照片，只記檔名
    var mine: Bool?  // 自己加的
    var ai: Bool?  // AI 加的
}

struct Slot: Codable, Hashable, Sendable {
    var day: Int
    var part: Part
    var off: Bool?  // 在路上，不能排
    var rest: Bool = false  // 留白
    var items: [Stop] = []
}

struct TripDraft: Codable, Hashable, Sendable {
    var tweaks: [Tweak]?
    var city: String?  // 第一版只有 "seoul"
    var base: BaseKey?  // 這趟住哪一帶。沒填就用「我」裡的
    var stayName: String?  // 住宿的名字，使用者自己打的，沒查證
    var name: String?  // 使用者取的名字。沒取就叫「首爾幾天」
    var cover: String?  // 封面照片，只記檔名
    var start: String  // YYYY-MM-DD
    var days: Int
    var arrive: Part
    var leave: Part
    var people: Int
}

/// 使用者自己記的一筆花費，金額是韓元
struct Spend: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var krw: Double
    var note: String?  // 花在哪，使用者自己打的
    var day: Int?  // 旅途中記的才有：第幾天
}

/// TS 的 Trip extends TripDraft：這裡把 TripDraft 的欄位攤平寫在前面
struct Trip: Codable, Hashable, Sendable {
    var tweaks: [Tweak]?
    var city: String?
    var base: BaseKey?
    var stayName: String?
    var name: String?
    var cover: String?
    var start: String
    var days: Int
    var arrive: Part
    var leave: Part
    var people: Int
    var slots: [Slot] = []
    var flight: Double = 0
    var spend: [Spend]?  // 實際花的，一筆一筆記
    var rate: Double?  // 1000 韓元換多少台幣。使用者自己填的，app 不抓匯率
    var planBy: PlanBy?  // 這一版是誰排的。nil 當成 app 內建的排法（舊檔、現在的開一趟都是）
    var planAt: String?  // AI 排好的那一天，YYYY-MM-DD。內建的排法不寫
    var planMark: String?  // 剛排好那張卡第一次出現時，這一版的樣子（planMarkOf）。之後對不上就是改過了
    var aiUsed: Int?  // 這趟問了 AI 幾句（AI 有回的才算，見 Chat.swift 的 aiLeft）
}

/// 從行程學到的一條：以後不排某一站、某一類、某一種吃的。source 寫明是哪一次學到的
struct Learned: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var kind: LearnKind
    var key: String  // 地點代號、Cat 或 FoodKind 的字
    var n: String  // 給人看的名字
    var source: String
}

struct Settings: Codable, Hashable, Sendable {
    var stay: StayKind = .mid
    var base: BaseKey = .C
    var food: [FoodKind: Int] = [:]  // 0 不要、1 偶爾、2 常常、3 主力
    var allergy: [String] = []  // 過敏，不能出錯。記的是 ALLERGENS 的中文名
    var avoid: [String] = []  // 絕對不吃
    var meh: [String] = []  // 不愛，但可以
    var walk: Walk = .normal  // 一天能走多少
    var body: [BodyLimit] = []  // 身體上要避開的
    var learned: [Learned] = []  // 在行程上說「以後都不排」學到的
    var queue: QueueKind = .few
    var mealMax: Double = 0  // 0 是不限
    var budget: Double = 0  // 一天吃喝
    var play: [Cat: Int] = [:]  // 只會是 1 或 2
    var purposes: [Purpose] = []  // 旅行回來希望怎樣，可以好幾個，空的是都可以
    var tags: [String] = []  // 更細的興趣，先記著，接上 AI 才會用
    var wish: String = ""  // 其他想做的，使用者自己打的
    var pace: Pace = .mid
    var wake: Wake = .normal
    var move: Move = .transit
    var tuned: Bool = false  // 使用者自己回答過偏好了嗎
}

extension Settings {
    /// 讀舊檔：少了哪一欄就用 defaultSettings() 的值補，不會因為多了新欄位就整包讀不回來
    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        var out = defaultSettings()
        out.stay = try box.decodeIfPresent(StayKind.self, forKey: .stay) ?? out.stay
        out.base = try box.decodeIfPresent(BaseKey.self, forKey: .base) ?? out.base
        out.food = try box.decodeIfPresent([FoodKind: Int].self, forKey: .food) ?? out.food
        out.allergy = try box.decodeIfPresent([String].self, forKey: .allergy) ?? out.allergy
        out.avoid = try box.decodeIfPresent([String].self, forKey: .avoid) ?? out.avoid
        out.meh = try box.decodeIfPresent([String].self, forKey: .meh) ?? out.meh
        out.walk = try box.decodeIfPresent(Walk.self, forKey: .walk) ?? out.walk
        out.body = try box.decodeIfPresent([BodyLimit].self, forKey: .body) ?? out.body
        out.learned = try box.decodeIfPresent([Learned].self, forKey: .learned) ?? out.learned
        out.queue = try box.decodeIfPresent(QueueKind.self, forKey: .queue) ?? out.queue
        out.mealMax = try box.decodeIfPresent(Double.self, forKey: .mealMax) ?? out.mealMax
        out.budget = try box.decodeIfPresent(Double.self, forKey: .budget) ?? out.budget
        out.play = try box.decodeIfPresent([Cat: Int].self, forKey: .play) ?? out.play
        out.purposes = try box.decodeIfPresent([Purpose].self, forKey: .purposes) ?? out.purposes
        out.tags = try box.decodeIfPresent([String].self, forKey: .tags) ?? out.tags
        out.wish = try box.decodeIfPresent(String.self, forKey: .wish) ?? out.wish
        out.pace = try box.decodeIfPresent(Pace.self, forKey: .pace) ?? out.pace
        out.wake = try box.decodeIfPresent(Wake.self, forKey: .wake) ?? out.wake
        out.move = try box.decodeIfPresent(Move.self, forKey: .move) ?? out.move
        out.tuned = try box.decodeIfPresent(Bool.self, forKey: .tuned) ?? out.tuned
        self = out
    }
}

struct SeedFrom: Codable, Hashable, Sendable {
    var day: Int
    var part: Part
}

/// 下次再來：拿掉的站、自己想到還沒排的
struct Seed: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var n: String
    var a: String
    var why: String
    var stop: Stop?
    var from: SeedFrom?
}

struct BasketItem: Codable, Hashable, Sendable {
    var id: String?  // 還在行程裡的那一站的代號。收起來之後就只是紀錄
    var n: String
    var s: StopSize
    var c: Cat
    var ic: IconKey?
    var say: String?
    var kr: String?
    var lat: Double?
    var lng: Double?
    var day: Int?  // 第幾天去的
    var photos: [String]?
}

/// 去過的一趟
struct Basket: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var cover: String?
    var items: [BasketItem] = []
    var start: String?
    var days: Int?
}

struct ChatMsg: Codable, Hashable, Sendable {
    var r: ChatRole
    var t: String
    var changes: [String]?
    var ask: [String]?  // 確認卡上的每一行：這些要使用者按「套用」才改
    var askOps: String?  // 確認卡對應的 op（JSON）。按過或過期了就清掉
    var asked: Bool?  // 按了什麼：true 套用、false 不要；還沒按是 nil
    // 以下是片 2（跟 AI 講）加的，全部可以沒有，舊的存檔照樣讀得出來
    var day: Int?  // 講這句的時候在看第幾天（我說的、回的那一則都記）
    var stop: String?  // 講這句的時候在看哪一站（站的 id）。在看某一天時是 nil
    var local: Bool?  // true：手機自己算的，沒有問 AI
    var at: Double?  // 回的時間（1970 起算的秒數），畫面上寫「剛剛」或幾點
    var failed: String?  // 我說的那句沒有收到回覆。字是錯誤代碼，不知道就是空字串；有回覆了就清掉
    var undo: String?  // 這一輪改動在復原紀錄裡的記號。還是最後一步時才能「復原這次」
    var undone: Bool?  // 這一輪按過「復原這次」了
}

/// 排好了、先放在一邊的一趟。行程、對話、要先訂的勾選都跟著它
struct Shelved: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var trip: Trip
    var chat: [ChatMsg] = []
    var checks: [String: Bool] = [:]
    var debugDay: Int?
}

struct AppState: Codable, Hashable, Sendable {
    var settings: Settings = defaultSettings()
    var trip: Trip?  // 現在打開的這一趟
    var shelf: [Shelved] = []  // 其他排好的
    var seeds: [Seed] = []
    var pool: [String] = []  // 順路可去
    var checks: [String: Bool] = [:]
    var chat: [ChatMsg] = []
    var baskets: [Basket] = []
    var settingsDirty: Bool = false  // 設定改過、還沒套到這趟
    var aiConsent: Bool = false
    var guideSeen: Bool = false  // 「這趟」的操作說明看過了嗎
    var remind: Bool = false  // 出發前提醒還沒訂的站（本機通知）
    var debugDay: Int?  // 測試用：假裝今天是第幾天
}

extension AppState {
    /// 讀舊檔：少了哪一欄就用空白狀態的值補
    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        var out = AppState()
        out.settings = try box.decodeIfPresent(Settings.self, forKey: .settings) ?? out.settings
        out.trip = try box.decodeIfPresent(Trip.self, forKey: .trip)
        out.shelf = try box.decodeIfPresent([Shelved].self, forKey: .shelf) ?? []
        out.seeds = try box.decodeIfPresent([Seed].self, forKey: .seeds) ?? []
        out.pool = try box.decodeIfPresent([String].self, forKey: .pool) ?? []
        out.checks = try box.decodeIfPresent([String: Bool].self, forKey: .checks) ?? [:]
        out.chat = try box.decodeIfPresent([ChatMsg].self, forKey: .chat) ?? []
        out.baskets = try box.decodeIfPresent([Basket].self, forKey: .baskets) ?? []
        out.settingsDirty = try box.decodeIfPresent(Bool.self, forKey: .settingsDirty) ?? false
        out.aiConsent = try box.decodeIfPresent(Bool.self, forKey: .aiConsent) ?? false
        out.guideSeen = try box.decodeIfPresent(Bool.self, forKey: .guideSeen) ?? false
        out.remind = try box.decodeIfPresent(Bool.self, forKey: .remind) ?? false
        out.debugDay = try box.decodeIfPresent(Int.self, forKey: .debugDay)
        self = out
    }

    /// 存檔的字轉回狀態。讀不出來就回 nil，由呼叫的人決定怎麼辦（不要默默蓋掉舊檔）
    static func hydrate(_ data: Data?) -> AppState? {
        guard let data else { return AppState() }
        return try? JSONDecoder().decode(AppState.self, from: data)
    }
}
