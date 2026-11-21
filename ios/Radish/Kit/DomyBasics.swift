// Domy Design 的基本元件（SwiftUI 版）：文字、按鈕、圓鈕、按下回饋、震動。
// 照 @domy/design 的 DomyText、DomyButton、DomyIconButton 做，數值全部來自 T。
import SwiftUI
import UIKit

enum TextVariant {
    case largeTitle, title1, title2, title3, headline, body, callout, subheadline, footnote, caption

    var style: DomyTypeStyle {
        switch self {
        case .largeTitle: return T.TypeScale.largeTitle
        case .title1: return T.TypeScale.title1
        case .title2: return T.TypeScale.title2
        case .title3: return T.TypeScale.title3
        case .headline: return T.TypeScale.headline
        case .body: return T.TypeScale.body
        case .callout: return T.TypeScale.callout
        case .subheadline: return T.TypeScale.subheadline
        case .footnote: return T.TypeScale.footnote
        case .caption: return T.TypeScale.caption
        }
    }
}

enum TextTone {
    case primary, secondary, strong, destructive, onAccent, disabled

    var color: Color {
        switch self {
        case .primary: return C.textPrimary
        case .secondary: return C.textSecondary
        case .strong: return C.strong
        case .destructive: return C.destructive
        case .onAccent: return C.onAccent
        case .disabled: return C.textDisabled
        }
    }
}

/// 所有畫面上的字都用這個。用法：`DomyText("標題", .title2)`、`DomyText("說明", .footnote, tone: .secondary)`
struct DomyText: View {
    let text: String
    var variant: TextVariant = .body
    var tone: TextTone = .primary
    var weight: Font.Weight?
    var lines: Int?
    var align: TextAlignment = .leading
    var color: Color?
    /// 這段字是會變的數字（金額、計數）：換值時每一位數滾過去，不是直接跳
    var numeric: Bool = false

    init(
        _ text: String,
        _ variant: TextVariant = .body,
        tone: TextTone = .primary,
        weight: Font.Weight? = nil,
        lines: Int? = nil,
        align: TextAlignment = .leading,
        color: Color? = nil,
        numeric: Bool = false
    ) {
        self.text = text
        self.variant = variant
        self.tone = tone
        self.weight = weight
        self.lines = lines
        self.align = align
        self.color = color
        self.numeric = numeric
    }

    var body: some View {
        Text(text)
            .contentTransition(numeric ? .numericText() : .identity)
            .font(variant.style.font.weight(weight ?? variant.style.weight))
            .lineSpacing(variant.style.lineSpacing)
            .foregroundStyle(color ?? tone.color)
            .multilineTextAlignment(align)
            .lineLimit(lines)
            .fixedSize(horizontal: false, vertical: true)
    }
}

extension View {
    /// 讓一段字往左靠、佔滿整列寬（等於 RN 的 flex: 1）
    func fillLeading() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 震動。全部走這裡，之後要調手感只改一個地方
enum Haptic {
    static func select() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func notify(_ kind: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(kind)
    }
}

/// 按下時的回饋：一般縮小一點；系統開了「減少動態」就改成變淡，不做縮放
struct PressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? T.Motion.pressScale : 1)
            .opacity(configuration.isPressed && reduceMotion ? T.Motion.pressedOpacity : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

/// 列的按下回饋：整列底色變灰
struct RowPressStyle: ButtonStyle {
    var selected: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(selected ? C.soft : (configuration.isPressed ? C.surfaceMuted : Color.clear))
    }
}

enum ButtonVariant {
    case primary, secondary, plain, destructive
}

enum ButtonSize {
    case regular, compact
}

/// 一個畫面最多一顆 primary。危險操作用 destructive，不用產品色。
/// 停用時請換字（例：「整理中…」），不要只靠顏色變淡。
struct DomyButton: View {
    let title: String
    var variant: ButtonVariant = .primary
    var size: ButtonSize = .regular
    var disabled: Bool = false
    var fullWidth: Bool = false
    var haptic: Bool?
    var label: String?
    let action: () -> Void

    init(
        _ title: String,
        variant: ButtonVariant = .primary,
        size: ButtonSize = .regular,
        disabled: Bool = false,
        fullWidth: Bool = false,
        haptic: Bool? = nil,
        label: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.variant = variant
        self.size = size
        self.disabled = disabled
        self.fullWidth = fullWidth
        self.haptic = haptic
        self.label = label
        self.action = action
    }

    private var background: Color {
        if disabled { return C.surfaceMuted }
        switch variant {
        case .primary: return C.accent
        case .secondary: return C.surfaceMuted
        case .plain: return Color.clear
        case .destructive: return C.destructiveSoft
        }
    }

    private var foreground: Color {
        if disabled { return C.textDisabled }
        switch variant {
        case .primary: return C.onAccent
        case .secondary: return C.textPrimary
        case .plain: return C.strong
        case .destructive: return C.destructive
        }
    }

    var body: some View {
        let height: CGFloat = size == .compact ? T.Size.buttonCompact : T.Size.button
        let style: DomyTypeStyle = size == .compact ? T.TypeScale.callout : T.TypeScale.headline
        Button {
            if haptic ?? false { Haptic.select() }
            action()
        } label: {
            Text(title)
                .font(style.font)
                .foregroundStyle(foreground)
                .lineLimit(1)
                .padding(.horizontal, size == .compact ? T.Space.s4 : T.Space.s6)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .frame(height: height)
                .background(background, in: Capsule())
                .frame(minHeight: T.Size.touch)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(disabled)
        .accessibilityLabel(label ?? title)
    }
}

/// 導覽列兩側的白底圓鈕。給 title 是文字膠囊（例：「關閉」）；給 icon（SVG path）是圓鈕，label 一定要給
struct DomyIconButton: View {
    var title: String?
    var icon: String?
    let label: String
    var neutral: Bool = false
    let action: () -> Void

    init(
        title: String? = nil,
        icon: String? = nil,
        label: String,
        neutral: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.label = label
        self.neutral = neutral
        self.action = action
    }

    var body: some View {
        let color: Color = neutral ? C.textPrimary : (title == nil ? C.accent : C.strong)
        Button(action: action) {
            Group {
                if let title {
                    Text(title).font(T.TypeScale.callout.font).foregroundStyle(color)
                        .padding(.horizontal, T.Space.s4)
                } else if let icon {
                    LineIcon(icon, color: color)
                }
            }
            .frame(minWidth: T.Size.iconButton)
            .frame(height: T.Size.iconButton)
            .background(C.surface, in: Capsule())
            .domyElevation(T.Elevation.level1)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }
}

/// 1px 分隔線
struct Hairline: View {
    var body: some View {
        Rectangle().fill(C.separator).frame(height: T.Size.hairline)
    }
}
