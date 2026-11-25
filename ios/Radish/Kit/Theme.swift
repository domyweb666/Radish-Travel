// 蘿蔔旅行的產品色：蘿蔔橘。只有這款 App 用。
// 畫面一律用 T（尺寸、圓角、間距、字級）和 C（顏色），不准在畫面裡寫色碼和數字。
// 色碼只准出現在這個檔和 DomyTokens.swift。對比由 RadishUITests 以外的 ThemeTests 驗（見 ios/README.md）。
import SwiftUI

/// 尺寸、圓角、間距、字級的代號
typealias T = DomyTokens

/// 只有這款 App 用的尺寸，不放進套件
extension DomyTokens.Size {
    /// 這趟分頁最上面、跟天數分頁一起黏在上面的那張地圖多高。比路線半頁裡的（150）矮一點，下面還要留給這天的站
    static let tripMap: CGFloat = 136
}

extension DomyTheme {
    /// 蘿蔔橘，暖色畫布
    static let radish = DomyTheme(
        name: "radish",
        canvas: DomyTokens.Canvas.warm,
        accent: Color(domyLight: 0xB5501B, domyDark: 0xF0A064),
        onAccent: Color(domyLight: 0xFFFFFF, domyDark: 0x3A1A04),
        strong: Color(domyLight: 0x96400F, domyDark: 0xF7BE93),
        soft: Color(domyLight: 0xF8E2D2, domyDark: 0x40281A),
        tint: Color(domyLight: 0xFDF5EE, domyDark: 0x221710),
        bright: Color(domyLight: 0xFF9A3D, domyDark: 0xFF9A3D),
        onBright: Color(domyLight: 0x3A1A04, domyDark: 0x3A1A04)
    )
}

/// 這款 App 的所有顏色。淺色深色會自己跟著系統切換
enum C {
    private static let theme = DomyTheme.radish
    static let canvas = theme.canvas
    static let accent = theme.accent  // 主要按鈕底、開關啟用、選取圖示、進度
    static let onAccent = theme.onAccent  // 壓在 accent 上的字與圖示
    static let strong = theme.strong  // 產品色的文字、連結
    static let soft = theme.soft  // 選取中的分頁、選取列、選項膠囊的底
    static let tint = theme.tint  // 少數重點區塊的淡底
    static let bright = theme.bright  // 核心動作大按鈕
    static let onBright = theme.onBright

    static let surface = DomyTokens.Neutral.surface
    static let surfaceMuted = DomyTokens.Neutral.surfaceMuted
    static let separator = DomyTokens.Neutral.separator
    static let fieldBorder = DomyTokens.Neutral.fieldBorder
    static let textPrimary = DomyTokens.Neutral.textPrimary
    static let textSecondary = DomyTokens.Neutral.textSecondary
    static let textTertiary = DomyTokens.Neutral.textTertiary
    static let textDisabled = DomyTokens.Neutral.textDisabled
    static let destructive = DomyTokens.Neutral.destructive
    static let destructiveSoft = DomyTokens.Neutral.destructiveSoft
    static let shadow = DomyTokens.Neutral.shadow
}

/// 角色色：蘿蔔本身。它是內容，不是介面，淺深色都用同一組。
enum RadishColors {
    static let small = Color(domyLight: 0xFF9A3D, domyDark: 0xFF9A3D)  // 小站的橘蘿蔔
    static let smallLine = Color(domyLight: 0xD9741C, domyDark: 0xD9741C)
    static let big = Color(domyLight: 0xFAFAF5, domyDark: 0xFAFAF5)  // 大站的白蘿蔔
    static let bigLine = Color(domyLight: 0xCFCFC4, domyDark: 0xCFCFC4)
    static let leaf = Color(domyLight: 0x4F9D5B, domyDark: 0x4F9D5B)  // 葉子
    static let soil = Color(domyLight: 0xC9A27A, domyDark: 0xC9A27A)  // 土
}

/// 蘿蔔人：戴蘿蔔頭套的火柴人。頭套沿用上面的橘蘿蔔和葉子。
enum BuddyColors {
    static let ink = Color(domyLight: 0x2B2329, domyDark: 0x2B2329)  // 五官
    static let face = Color(domyLight: 0xFFFFFF, domyDark: 0xFFFFFF)  // 臉
    static let faceRim = Color(domyLight: 0xB85F12, domyDark: 0xB85F12)  // 臉外圈
    static let shine = Color(domyLight: 0xFFC48A, domyDark: 0xFFC48A)  // 頭套反光
    static let leafDark = Color(domyLight: 0x3B7F47, domyDark: 0x3B7F47)  // 中間那片葉子
    static let sweat = Color(domyLight: 0x7EC3EA, domyDark: 0x7EC3EA)  // 汗
}

extension View {
    /// 陰影：level1 給白底圓鈕，level2 給懸浮的分頁列和提示條
    func domyElevation(_ shadow: DomyShadow) -> some View {
        self.shadow(color: C.shadow.opacity(shadow.opacity), radius: shadow.radius, x: 0, y: shadow.y)
    }
}
