// App 本地的小元件，全部用 T 和 C 組起來。對應 mobile/src/components/ui.tsx。
// 規矩：兩款以上的 App 都要用，才搬進 Domy Design。
import SwiftUI

enum CardTone {
    case surface, tint
}

/// 白底卡片。裡面的東西直向排、間距 s3
struct Card<Content: View>: View {
    var tone: CardTone = .surface
    @ViewBuilder var content: Content

    init(tone: CardTone = .surface, @ViewBuilder content: () -> Content) {
        self.tone = tone
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: T.Radius.xl, style: .continuous)
        VStack(alignment: .leading, spacing: T.Space.s3) {
            content
        }
        .padding(T.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone == .tint ? C.tint : C.surface, in: shape)
        .overlay(shape.strokeBorder(tone == .tint ? C.soft : Color.clear, lineWidth: T.Size.hairline))
    }
}

/// 分段切換：同一頁裡換內容用。options 是（值, 顯示的字）
struct Segmented<K: Hashable>: View {
    let value: K
    let options: [(K, String)]
    let onChange: (K) -> Void

    init(value: K, options: [(K, String)], onChange: @escaping (K) -> Void) {
        self.value = value
        self.options = options
        self.onChange = onChange
    }

    var body: some View {
        HStack(spacing: T.Space.s1 / 2) {
            ForEach(options.indices, id: \.self) { index in
                let option: (K, String) = options[index]
                let isOn: Bool = option.0 == value
                Button {
                    onChange(option.0)
                } label: {
                    DomyText(option.1, .subheadline, tone: isOn ? .primary : .secondary, weight: .semibold, lines: 1)
                        .frame(maxWidth: .infinity)
                        .frame(height: T.Size.pickerHeight)
                        .background(
                            isOn ? C.surface : Color.clear,
                            in: RoundedRectangle(cornerRadius: T.Radius.sm, style: .continuous)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? [.isSelected] : [])
            }
        }
        .padding(T.Space.s1 / 2)
        .background(C.surfaceMuted, in: RoundedRectangle(cornerRadius: T.Radius.md, style: .continuous))
    }
}

/// 選項膠囊：選到的用 Soft 底＋Strong 字。onSurface 是放在白卡上時用灰底
struct Chip: View {
    let label: String
    var selected: Bool = false
    var onSurface: Bool = false
    var disabled: Bool = false
    var action: (() -> Void)?

    init(
        _ label: String,
        selected: Bool = false,
        onSurface: Bool = false,
        disabled: Bool = false,
        action: (() -> Void)? = nil
    ) {
        self.label = label
        self.selected = selected
        self.onSurface = onSurface
        self.disabled = disabled
        self.action = action
    }

    var body: some View {
        let tone: TextTone = disabled ? .disabled : (selected ? .strong : .primary)
        let fill: Color = selected ? C.soft : (onSurface ? C.surfaceMuted : C.surface)
        Button {
            action?()
        } label: {
            DomyText(label, .callout, tone: tone, lines: 1)
                .padding(.horizontal, T.Space.s4)
                .frame(minHeight: T.Size.buttonCompact)
                .background(fill, in: Capsule())
                .frame(minHeight: T.Size.touch)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(disabled || action == nil)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// 常駐入口膠囊：前面一個小圖示，白底細框（這趟標題下面的檢查這趟、須知）。
/// 看起來跟選項膠囊不一樣，點了是推進一頁，不是選一個值
struct EntryChip: View {
    let label: String
    let icon: String
    let action: () -> Void

    init(_ label: String, icon: String, action: @escaping () -> Void) {
        self.label = label
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: T.Space.s1 + T.Space.s1 / 2) {
                LineIcon(icon, size: IconPaths.chipSize)
                DomyText(label, .subheadline, weight: .semibold, lines: 1)
            }
            .padding(.horizontal, T.Space.s4 - T.Space.s1 / 2)
            .frame(minHeight: T.Size.buttonCompact)
            .background(C.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(C.separator, lineWidth: T.Size.hairline))
            .frame(minHeight: T.Size.touch)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
    }
}

/// 會自動換行的橫排（RN 的 flexWrap）
struct FlowLayout: Layout {
    var spacing: CGFloat = T.Space.s2
    var lineSpacing: CGFloat = 0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return rows.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        for (index, point) in rows.points.enumerated() {
            let origin = CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y)
            subviews[index].place(at: origin, anchor: .topLeading, proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (points: [CGPoint], size: CGSize) {
        var points: [CGPoint] = []
        var cursorX: CGFloat = 0
        var cursorY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for sub in subviews {
            let size: CGSize = sub.sizeThatFits(.unspecified)
            if cursorX > 0 && cursorX + size.width > width {
                cursorX = 0
                cursorY += rowHeight + lineSpacing
                rowHeight = 0
            }
            points.append(CGPoint(x: cursorX, y: cursorY))
            cursorX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, cursorX - spacing)
        }
        return (points, CGSize(width: maxX, height: cursorY + rowHeight))
    }
}

/// 一排膠囊，放不下會換行
struct ChipRow<Content: View>: View {
    @ViewBuilder var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        FlowLayout(spacing: T.Space.s2) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum TagTone {
    case neutral, accent, warn
}

/// 小標籤：只放一眼要看到的狀態
struct Tag: View {
    let label: String
    var tone: TagTone = .neutral

    init(_ label: String, tone: TagTone = .neutral) {
        self.label = label
        self.tone = tone
    }

    var body: some View {
        let fill: Color = tone == .neutral ? C.surfaceMuted : (tone == .accent ? C.soft : C.destructiveSoft)
        let text: TextTone = tone == .neutral ? .secondary : (tone == .accent ? .strong : .destructive)
        DomyText(label, .caption, tone: text)
            .padding(.horizontal, T.Space.s2)
            .padding(.vertical, T.Space.s1 / 2)
            .background(fill, in: Capsule())
    }
}

/// 一排小標籤，放不下會換行
struct TagRow<Content: View>: View {
    @ViewBuilder var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        FlowLayout(spacing: T.Space.s2, lineSpacing: T.Space.s2) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 一段要讓人注意的話，可以帶一顆按鈕
struct Banner: View {
    let text: String
    var actionTitle: String?
    var action: (() -> Void)?

    init(_ text: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.text = text
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        Card(tone: .tint) {
            DomyText(text, .subheadline, tone: .secondary)
            if let actionTitle, let action {
                DomyButton(actionTitle, variant: .secondary, size: .compact, action: action)
            }
        }
    }
}

/// 打勾的列：檢查表、要先訂的。放在 DomySection 或 Card 裡
struct CheckRow: View {
    let checked: Bool
    let title: String
    var note: String?
    let action: () -> Void

    init(checked: Bool, title: String, note: String? = nil, action: @escaping () -> Void) {
        self.checked = checked
        self.title = title
        self.note = note
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: T.Space.s3) {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .font(T.TypeScale.title2.font)
                    .foregroundStyle(checked ? C.accent : C.fieldBorder)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: T.Space.s1) {
                    DomyText(title, .body, tone: checked ? .secondary : .primary)
                    if let note {
                        DomyText(note, .footnote, tone: .secondary)
                    }
                }
                .fillLeading()
            }
            .padding(.vertical, T.Space.s3)
            .frame(minHeight: T.Size.row)
            .padding(.horizontal, T.Space.s4)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .padding(.horizontal, -T.Space.s4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(checked ? "已打勾" : "還沒打勾")
        .accessibilityAddTraits(.isButton)
    }
}

/// 卡片裡的小標（ui.tsx 的 Label；SwiftUI 已經有 Label，所以改名）
struct FieldLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        DomyText(text, .footnote, tone: .secondary)
    }
}

/// 列裡的一段文字（給 DomySection 當一列用），右邊可以放東西
struct TextRow<Right: View>: View {
    let title: String
    var note: String?
    @ViewBuilder var right: Right

    init(_ title: String, note: String? = nil, @ViewBuilder right: () -> Right) {
        self.title = title
        self.note = note
        self.right = right()
    }

    var body: some View {
        HStack(spacing: T.Space.s3) {
            VStack(alignment: .leading, spacing: T.Space.s1) {
                DomyText(title, .body)
                if let note, !note.isEmpty {
                    DomyText(note, .footnote, tone: .secondary)
                }
            }
            .fillLeading()
            right
        }
        .padding(.vertical, T.Space.s3)
        .frame(minHeight: T.Size.row)
    }
}

extension TextRow where Right == EmptyView {
    init(_ title: String, note: String? = nil) {
        self.init(title, note: note) { EmptyView() }
    }
}
