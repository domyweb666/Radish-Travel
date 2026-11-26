// 首爾範例資料。內容在 Resources/seoul.json，是 ios/tools/export-seoul.ts 從
// mobile/src/data/seoul.ts 轉出來的，全部是候選、粗估、未核對。
// 下面的全域常數名字跟 TS 一樣（AREA、PLACES…），規則搬過來時可以逐行對照。
import Foundation

struct HotelPt: Codable, Hashable, Sendable {
    var lat: Double
    var lng: Double
    var n: String
    var kr: String
}

struct FoodText: Codable, Hashable, Sendable {
    var name: String
    var desc: String
}

struct StayText: Codable, Hashable, Sendable {
    var name: String
    /// 一晚大約多少（台幣，粗估，沒核對）。只拿來估花費
    var perNight: Double
    /// 住哪一類，例如「青旅、民宿」。五星級飯店名字已經講清楚，沒有這句
    var what: String?
}

extension StayText {
    /// 選項上的字：「便宜就好（青旅、民宿）」
    var label: String {
        guard let w = what, !w.isEmpty else { return name }
        return "\(name)（\(w)）"
    }
}

struct Allergen: Codable, Hashable, Sendable {
    var n: String
    var kr: String
}

/// 一條要讓人知道的事。status 是核對狀態（二手核對／來源較舊／未核對），照實顯示
struct Fact: Codable, Hashable, Sendable {
    var text: String
    var status: String
    var checked: String
    var source: String
}

struct TabooFact: Codable, Hashable, Sendable {
    var level: Int  // 1 知道比較好、2 會被白眼、3 會出事
    var text: String
    var result: String
    var status: String
    var checked: String
    var source: String
}

enum CheckGroup: String, Codable, Sendable {
    case todo, pack
}

/// 行前檢查表的一條。id 不要改，使用者打的勾是照 id 存的
struct CheckItem: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var group: CheckGroup
    var text: String
    var status: String
    var checked: String
    var source: String
}

/// 吃與買的一條（TS 的 Pick）
struct Tip: Codable, Hashable, Sendable {
    var n: String
    var kr: String?
    var note: String
}

struct SeoulData: Codable, Sendable {
    var dataChecked: String
    var area: [AreaKey: String]
    var adj: [AreaKey: [AreaKey]]
    var hotel: [BaseKey: HotelPt]
    var places: [Place]
    var cat: [Cat: String]
    var food: [FoodKind: FoodText]
    var flv: [String]
    var avoid: [String]
    var meh: [String]
    var allergens: [Allergen]
    var purpose: [Purpose: String]
    var part: [Part: String]
    var pullLines: [String]
    var stay: [StayKind: StayText]
    var taboo: [TabooFact]
    var tabooLevel: [String: String]
    var diff: [Fact]
    var checklist: [CheckItem]
    var noBring: [Fact]
    var sos: [Fact]
    var eats: [Tip]
    var dishes: [Tip]
    var gifts: [Tip]
    var giftRules: [String]

    static let shared: SeoulData = load()

    private static func load() -> SeoulData {
        #if SWIFT_PACKAGE
            let bundle = Bundle.module
        #else
            let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "seoul", withExtension: "json"),
            let data = try? Data(contentsOf: url)
        else { fatalError("找不到 seoul.json：資料包沒有跟著 app 一起打包") }
        do {
            return try JSONDecoder().decode(SeoulData.self, from: data)
        } catch {
            fatalError("seoul.json 讀不出來：\(error)")
        }
    }
}

let DATA_CHECKED: String = SeoulData.shared.dataChecked
let AREA: [AreaKey: String] = SeoulData.shared.area
let ADJ: [AreaKey: [AreaKey]] = SeoulData.shared.adj
let HOTEL: [BaseKey: HotelPt] = SeoulData.shared.hotel
/// 候選地點。星級（star）在這裡補齊：新加的真店沒寫在資料包裡，見 Stars.swift
let PLACES: [Place] = withStars(mergePlaces(SeoulData.shared.places, SeoulChecked.shared))
let CAT: [Cat: String] = SeoulData.shared.cat
let FOOD: [FoodKind: FoodText] = SeoulData.shared.food
let FLV: [String] = SeoulData.shared.flv
let AVOID: [String] = SeoulData.shared.avoid
let MEH: [String] = SeoulData.shared.meh
let ALLERGENS: [Allergen] = SeoulData.shared.allergens
let PURPOSE: [Purpose: String] = SeoulData.shared.purpose
let PART: [Part: String] = SeoulData.shared.part
let PULL_LINES: [String] = SeoulData.shared.pullLines
let STAY: [StayKind: StayText] = SeoulData.shared.stay
let TABOO: [TabooFact] = SeoulData.shared.taboo
let TABOO_LEVEL: [Int: String] = Dictionary(
    uniqueKeysWithValues: SeoulData.shared.tabooLevel.compactMap { pair in
        Int(pair.key).map { ($0, pair.value) }
    })
let DIFF: [Fact] = SeoulData.shared.diff
let CHECKLIST: [CheckItem] = SeoulData.shared.checklist
let NO_BRING: [Fact] = SeoulData.shared.noBring
let SOS: [Fact] = SeoulData.shared.sos
let EATS: [Tip] = SeoulData.shared.eats
let DISHES: [Tip] = SeoulData.shared.dishes
let GIFTS: [Tip] = SeoulData.shared.gifts
let GIFT_RULES: [String] = SeoulData.shared.giftRules

extension Dictionary {
    /// 資料表查值用：`AREA[need: .A]`。資料包少了該有的鍵是打包錯誤，直接停下來比默默顯示空白好
    subscript(need key: Key) -> Value {
        guard let value = self[key] else { fatalError("資料表少了 \(key)") }
        return value
    }
}
