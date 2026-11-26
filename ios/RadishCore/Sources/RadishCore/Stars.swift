// 星級：第一次來首爾的外國遊客，多想去這個地方。只看觀光熱門程度，跟誰付錢、有沒有合作都沒關係（排序沒有私心）。
//   3 第一次來幾乎都會去
//   2 值得排
//   1 在地人、或有特定興趣的人才會專程去
// 全部是估的：調查問的是「一帶」（明洞、弘大、江南），不是我們資料包裡的一站一站，所以每一站幾顆星是照下面的排名再加判斷。
// 畫面上、給 AI 的字都要講明是估的。每一站的理由寫在 docs/星級依據.md。
//
// 依據（2026-11-26 查）：
// - 韓國文化觀光研究院《2024 外來觀光客調查 第 3 季暫定值》：外國遊客最喜歡的訪問地 明洞 16.2%、景福宮 7.8%、弘大 7.5%、江南 4.5%
//   報導：https://v.daum.net/v/6xbv4YmeJw
// - 首爾 AI 財團 2025 年外國人流動人口（2026-07 發表）：一天平均 明洞 100,910 人、N 首爾塔 57,370、三成站・COEX 46,813、
//   江南站 41,210、弘大一帶 40,213；比前一年多最多的是 DDP、弘大、駱山公園、廣藏市場
//   報導：https://www.newsis.com/view/NISX20260721_0003717515
// - 首爾觀光財團 2023 外來觀光客實態調查（1,600 人）：去過的地方 明洞第一、弘大 52.8%、江南 45.9%
//   報導：https://view.asiae.co.kr/en/article/2024062111555238517
// 2024、2025 年外來觀光客調查的全年報告裡「去過哪裡」的表沒有查到，查到再回來改。
import Foundation

/// 「挑一間」拆出來的真店（seoul-checked.json 的 add）沒有 star 欄位，星級寫在這裡。
/// seoul-checked.json 是核對資料，不放估的東西
let ADDED_STAR: [String: Int] = [
    "p4a": 2, "p4b": 2, "p4c": 1,
    "p5a": 2, "p5b": 2,
    "p13c": 2,
    "p14a": 2, "p14b": 2,
    "p15a": 1, "p15b": 1,
    "p16a": 2, "p16b": 1,
    "p20a": 1, "p20b": 1,
    "p22a": 1, "p22b": 1,
    "p26a": 1, "p26b": 1, "p26c": 1,
    "p27": 2,
    "p30a": 1, "p30b": 1, "p30c": 1,
    "p33a": 1, "p33b": 1, "p33c": 1,
    "p34a": 1, "p34b": 1,
    "p35a": 1, "p35b": 1, "p35c": 1,
    "p47a": 1, "p47b": 1, "p47c": 1,
]

/// 漏寫星級的時候當幾顆。取中間，不讓排序因為漏寫偏到哪一邊；測試會擋漏寫
let STAR_MISSING: Int = 2

/// 一站幾顆星，1 到 3。資料包有寫用資料包的，新加的真店照 ADDED_STAR，
/// 都沒有就看它是從哪一個「挑一間」拆出來的，用那一個的
func starOf(_ p: Place) -> Int {
    if let s = p.star { return min(3, max(1, s)) }
    if let s = ADDED_STAR[p.id] { return min(3, max(1, s)) }
    let group: String = placeGroup(p.id)
    if group != p.id {
        let parent: Place? = SeoulData.shared.places.first { (q: Place) -> Bool in q.id == group }
        if let s = parent?.star { return min(3, max(1, s)) }
    }
    return STAR_MISSING
}

/// 讀資料包時把每一站的星級補齊，之後用 p.star 就好
func withStars(_ places: [Place]) -> [Place] {
    return places.map { (p: Place) -> Place in
        var out: Place = p
        out.star = starOf(p)
        return out
    }
}

/// 照代號找地點；去過的紀錄沒有代號（或代號對不到）時，用中文名找
private func placeOfVisit(_ it: BasketItem, _ places: [Place]) -> Place? {
    if let id = it.id, let hit = places.first(where: { (p: Place) -> Bool in p.id == id }) {
        return hit
    }
    let name: String = it.n.trimmingCharacters(in: .whitespacesAndNewlines)
    if name.isEmpty { return nil }
    return places.first { (p: Place) -> Bool in p.n == name }
}

/// 以前收起來的旅行裡，每個地點去過幾趟（地點代號 → 趟數）。
/// 一趟裡同一個地方去兩次算一次。自己加的、AI 加的、資料包裡沒有的不算
func visitedOf(_ baskets: [Basket], _ places: [Place] = PLACES) -> [String: Int] {
    var out: [String: Int] = [:]
    for b in baskets {
        var seen: Set<String> = []
        for it in b.items {
            guard let p = placeOfVisit(it, places) else { continue }
            if seen.contains(p.id) { continue }
            seen.insert(p.id)
            out[p.id] = (out[p.id] ?? 0) + 1
        }
    }
    return out
}

/// 星級加多少分。排行程的分數是整數一階一階的：使用者說喜歡一類 +2、最愛 +4，旅行目的 +1 到 +2。
/// 第一次來：三星 +1.5、二星 +0.5。比「喜歡」的 +2 小，所以使用者自己說過的喜好還是贏。
/// 去過首爾：縮成三分之一（三星 +0.5、二星 +0.25）。去過的那幾站本來就往後排，剩下的照喜好排得比較深入。
/// 排行程時，那一帶最好的大站的這個分數也加進那一帶的分數（PlanGenerate.swift 的 areaScore）
func starBonus(_ star: Int, firstTime: Bool) -> Double {
    switch star {
    case 3: return firstTime ? 1.5 : 0.5
    case 2: return firstTime ? 0.5 : 0.25
    default: return 0
    }
}

/// 第一次來、排到三星的那一站要講的那句。是估的，不講成確定
let STAR_FIRST_WHY: String = "估計第一次來首爾的人多半會去"

/// 去過的站，真的沒別的可排才排進來時講的那句
func visitedWhy(_ times: Int) -> String {
    if times <= 1 { return "你上次來去過，這一帶沒別的可排" }
    return "你之前來去過 \(times) 次，這一帶沒別的可排"
}

/// 畫面上的星星：「★★★」「★★☆」「★☆☆」
func starMarks(_ star: Int) -> String {
    let n: Int = min(3, max(1, star))
    return String(repeating: "★", count: n) + String(repeating: "☆", count: 3 - n)
}

/// 讀螢幕報的字
func starSpoken(_ star: Int) -> String {
    let n: Int = min(3, max(1, star))
    return "估計熱門度 \(n) 顆星"
}

/// 一段清單底下講一次就好的說明
let STAR_NOTE: String = "星星是估的：第一次來首爾的外國遊客多想去，三顆是幾乎都會去。"
