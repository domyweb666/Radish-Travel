// 建議停留：一站大概待多久（QC-0013 #96）。mobile/ 沒有對應的 TS。
// 首爾資料包（seoul.json）和核對資料（seoul-checked.json）都沒有停留時間，排行程也只分上午、下午、晚上，
// 所以這裡照大站小站、種類、圖示粗估。畫面上一定要標「粗估」，不講成查過的事。
import Foundation

/// 一站建議待多久，例如「約 2 小時」。自己加的站不知道是什麼地方，回 nil
func suggestedStay(_ stop: Stop) -> String? {
    if stop.mine == true { return nil }
    return stayGuess(stop.s, stop.c, stop.ic, stop.a)
}

/// 首爾資料包裡的地點（不在這趟裡的那一頁用）
func suggestedStay(_ p: Place) -> String {
    return stayGuess(p.s, p.c, p.ic, p.a)
}

private func stayGuess(_ s: StopSize, _ c: Cat, _ ic: IconKey?, _ a: AreaKey?) -> String {
    let base: String = iconStay(ic) ?? (s == .L ? bigStay(c) : smallStay(c))
    // 近郊（愛寶樂園、南怡島、水原華城那一帶）光來回就要好幾個小時
    if a == AreaKey.J { return base + "，來回車程另外算" }
    return base
}

/// 有指定圖示的，比種類更準一點
private func iconStay(_ ic: IconKey?) -> String? {
    guard let ic else { return nil }
    switch ic {
    case .spa: return "約 2 到 3 小時"
    case .boat: return "約 1 小時"
    case .view: return "約 1 小時"
    case .market: return "約 1 到 2 小時"
    default: return nil
    }
}

/// 主要景點
private func bigStay(_ c: Cat) -> String {
    switch c {
    case .fun: return "約 5 小時以上"
    case .nature: return "約 3 小時"
    case .sight, .art, .shop: return "約 2 到 3 小時"
    case .night, .kpop: return "約 2 小時"
    case .eat, .cafe: return "約 1 到 2 小時"
    }
}

/// 順路的小地方
private func smallStay(_ c: Cat) -> String {
    switch c {
    case .shop, .art, .fun: return "約 1 到 2 小時"
    case .night: return "約 2 小時"
    case .eat, .cafe, .sight, .nature, .kpop: return "約 1 小時"
    }
}
