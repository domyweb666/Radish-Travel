// 圖示：分頁列四個、地點種類十四個。種類只靠形狀分，底色統一用產品色的 Soft。
// 對應 mobile/src/components/icons.tsx。path 是 24×24 的 SVG 線條，由 svgPath（RadishShape.swift）解析。
import SwiftUI

/// 一個 24×24 的線條圖示。d 是 SVG path
struct LineIcon: View {
    let d: String
    var color: Color = C.textPrimary
    var size: CGFloat = IconPaths.tabSize

    init(_ d: String, color: Color = C.textPrimary, size: CGFloat = IconPaths.tabSize) {
        self.d = d
        self.color = color
        self.size = size
    }

    var body: some View {
        let scale: CGFloat = size / IconPaths.viewBox
        svgPath(d)
            .applying(CGAffineTransform(scaleX: scale, y: scale))
            .stroke(color, style: StrokeStyle(lineWidth: IconPaths.stroke, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

enum IconPaths {
    static let viewBox: CGFloat = 24  // domy-ignore: SVG 的座標格，不是介面尺寸
    static let tabSize: CGFloat = 22  // domy-ignore: 跟 @domy/design 分頁列的圖示一樣大
    static let stroke: CGFloat = 2  // domy-ignore: 圖示線寬
    static let chipSize: CGFloat = 18  // domy-ignore: 常駐入口膠囊裡的小圖示，照線框 A1

    static let tabTrip =
        "M6 20a2 2 0 1 0 0-4 2 2 0 0 0 0 4zM18 8a2 2 0 1 0 0-4 2 2 0 0 0 0 4zM8 18h6a3 3 0 0 0 0-6h-4a3 3 0 0 1 0-6h6"
    static let tabPrep = "M9 6h11M9 12h11M9 18h11M4 6l1 1 1.5-2M4 12l1 1 1.5-2M4 18l1 1 1.5-2"
    static let tabBasket = "M4 10h16l-1.5 9h-13zM8 10l3-6M16 10l-3-6M9 14v2M12 14v2M15 14v2"
    static let tabTrips = "M4 8h16v11H4zM9 8V5h6v3M4 13h16"
    static let tabMe = "M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM4 21a8 8 0 0 1 16 0"
    /// 問 AI：對話框
    static let tabAsk = "M4 5h16v11H10l-6 4zM8 9.5h8M8 12.5h5"
    /// 更多：三個點
    static let more = "M5 12h.01M12 12h.01M19 12h.01"
    /// 檢查這趟：打勾的清單（原本行前分頁的圖示）
    static let check = tabPrep
    /// 須知：圓圈裡一個 i
    static let notes = "M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18zM12 11v5M12 8h.01"
    static let send = "M12 19V5M5 12l7-7 7 7"
    /// 加一個：加號（一站頁的「加照片」方塊）
    static let plus = "M12 5v14M5 12h14"
    static let sprout = "M12 21v-9M12 14c-5 0-7-3-7-7 5 0 7 3 7 7zM12 11c0-4 2-6 7-6 0 4-2 6-7 6z"
}

private struct CatIconSpec {
    let name: String
    let d: String
}

private func catIconSpec(_ key: IconKey) -> CatIconSpec {
    switch key {
    case .eat:
        return CatIconSpec(name: "餐廳", d: "M7 3v8M5 3v4a2 2 0 0 0 4 0V3M7 11v10M16 21V3c-2 2-3 5-2 9h2")
    case .market:
        return CatIconSpec(
            name: "市場",
            d: "M4 9l1-5h14l1 5M5 9v11h14V9M4 9c0 2.5 4 2.5 4 0 0 2.5 4 2.5 4 0 0 2.5 4 2.5 4 0 0 2.5 4 2.5 4 0"
                + "M10 20v-5h4v5")
    case .shop:
        return CatIconSpec(name: "逛街", d: "M6 8h12l1 12H5L6 8zM9 8V6a3 3 0 0 1 6 0v2")
    case .fun:
        return CatIconSpec(name: "遊樂與體驗", d: "M4 7h16v3a2 2 0 0 0 0 4v3H4v-3a2 2 0 0 0 0-4V7zM14 7v10")
    case .sight:
        return CatIconSpec(
            name: "古蹟地標", d: "M3 20h18M5 20v-8M9 20v-8M15 20v-8M19 20v-8M3 12h18M12 4l9 6H3l9-6z")
    case .art:
        return CatIconSpec(name: "博物館美術館", d: "M4 5h16v14H4zM4 16l4-4 4 4 3-3 5 5M15 9.5h.01")
    case .nature:
        return CatIconSpec(name: "公園", d: "M12 21v-6M12 15a5 5 0 0 1-4-8 4 4 0 0 1 8 0 5 5 0 0 1-4 8z")
    case .cafe:
        return CatIconSpec(
            name: "咖啡廳", d: "M5 9h11v6a4 4 0 0 1-4 4H9a4 4 0 0 1-4-4V9zM16 10h2a2 2 0 0 1 0 5h-2M8 3v3M12 3v3")
    case .night:
        return CatIconSpec(name: "夜生活", d: "M20 14A8 8 0 1 1 10 4a6 6 0 0 0 10 10z")
    case .kpop:
        return CatIconSpec(
            name: "追星",
            d: "M9 18V6l10-2v12M9 18a3 3 0 1 1-6 0 3 3 0 0 1 6 0zM19 16a3 3 0 1 1-6 0 3 3 0 0 1 6 0z")
    case .spa:
        return CatIconSpec(
            name: "汗蒸幕與溫泉",
            d: "M4 17c0 3 16 3 16 0M8 4c-1.5 2 1.5 3 0 6M12 4c-1.5 2 1.5 3 0 6M16 4c-1.5 2 1.5 3 0 6")
    case .boat:
        return CatIconSpec(name: "遊船", d: "M3 17l2 3h14l2-3zM5 17v-5h14v5M12 12V5l5 4")
    case .view:
        return CatIconSpec(name: "展望台", d: "M12 3v18M8 21h8M9.5 9h5l-1-4h-3zM10 9l-2 12M14 9l2 12")
    case .pin:
        return CatIconSpec(
            name: "自己加的",
            d: "M12 21s7-6 7-11a7 7 0 0 0-14 0c0 5 7 11 7 11zM12 12a2 2 0 1 0 0-4 2 2 0 0 0 0 4z")
    }
}

private func catToIcon(_ cat: Cat) -> IconKey {
    switch cat {
    case .eat: return .eat
    case .shop: return .shop
    case .fun: return .fun
    case .sight: return .sight
    case .art: return .art
    case .nature: return .nature
    case .cafe: return .cafe
    case .night: return .night
    case .kpop: return .kpop
    }
}

/// 一站該用哪個圖示：自己加的用圖釘，有指定圖示用指定的，不然照種類
func iconKeyOf(c: Cat, ic: IconKey?, mine: Bool?) -> IconKey {
    if mine == true { return .pin }
    return ic ?? catToIcon(c)
}

/// 種類的名字（給讀螢幕軟體念，也當小標）
func kindName(_ it: Stop) -> String {
    catIconSpec(iconKeyOf(c: it.c, ic: it.ic, mine: it.mine)).name
}

func kindName(_ it: BasketItem) -> String {
    catIconSpec(iconKeyOf(c: it.c, ic: it.ic, mine: nil)).name
}

func kindName(_ it: Place) -> String {
    catIconSpec(iconKeyOf(c: it.c, ic: it.ic, mine: nil)).name
}

/// 地點種類圖示：Soft 底的圓，產品色線條
struct CatIcon: View {
    let key: IconKey

    init(_ it: Stop) {
        self.key = iconKeyOf(c: it.c, ic: it.ic, mine: it.mine)
    }

    init(_ it: BasketItem) {
        self.key = iconKeyOf(c: it.c, ic: it.ic, mine: nil)
    }

    init(_ it: Place) {
        self.key = iconKeyOf(c: it.c, ic: it.ic, mine: nil)
    }

    var body: some View {
        let spec: CatIconSpec = catIconSpec(key)
        LineIcon(spec.d, color: C.strong)
            .frame(width: T.Size.iconButton, height: T.Size.iconButton)
            .background(C.soft, in: Circle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spec.name)
    }
}
