// Domy Design 的分組與列（SwiftUI 版）：DomySection、設定列、內容列、輸入框、空狀態。
// 照 @domy/design 的同名元件做，數值全部來自 T。
import SwiftUI

/// 分組：標題＋一張白卡，卡裡的列之間自動加 1px 分隔線。
/// 相關的列放進同一個 Section，不要每列各包一張卡。
struct DomySection<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: T.Space.s2) {
            if let title {
                DomyText(title, .title3)
                    .padding(.horizontal, T.Space.s1)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: 0) {
                Group(subviews: content) { subviews in
                    ForEach(subviews) { sub in
                        if sub.id != subviews.first?.id {
                            Hairline()
                        }
                        sub
                    }
                }
            }
            .padding(.horizontal, T.Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(C.surface)
            .clipShape(RoundedRectangle(cornerRadius: T.Radius.xl, style: .continuous))
            if let footer {
                DomyText(footer, .footnote, tone: .secondary)
                    .padding(.horizontal, T.Space.s4)
            }
        }
    }
}

/// 向右的小箭頭
struct Chevron: View {
    var color: Color = C.textTertiary

    var body: some View {
        Image(systemName: "chevron.right")
            .font(T.TypeScale.footnote.font.weight(.semibold))
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}

/// 設定列：右邊灰字＋箭頭，點了進下一頁。沒給 action 就只是顯示。列本身保持中性。
struct SettingsRow: View {
    let label: String
    var value: String?
    var destructive: Bool = false
    var action: (() -> Void)?

    init(_ label: String, value: String? = nil, destructive: Bool = false, action: (() -> Void)? = nil) {
        self.label = label
        self.value = value
        self.destructive = destructive
        self.action = action
    }

    private var row: some View {
        HStack(spacing: T.Space.s3) {
            DomyText(label, .body, tone: destructive ? .destructive : .primary).fillLeading()
            if let value {
                DomyText(value, .body, tone: .secondary, align: .trailing)
            }
            if action != nil {
                Chevron()
            }
        }
        .padding(.vertical, T.Space.s2)
        .frame(minHeight: T.Size.row)
        .padding(.horizontal, T.Space.s4)
        .contentShape(Rectangle())
    }

    var body: some View {
        Group {
            if let action {
                Button(action: action) { row }
                    .buttonStyle(RowPressStyle())
            } else {
                row
            }
        }
        .padding(.horizontal, -T.Space.s4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(value.map { "\(label)，\($0)" } ?? label)
        .accessibilityAddTraits(action == nil ? [] : .isButton)
    }
}

/// 設定列：開關，開啟時用產品色
struct ToggleRow: View {
    let label: String
    @Binding var isOn: Bool
    var disabled: Bool = false

    init(_ label: String, isOn: Binding<Bool>, disabled: Bool = false) {
        self.label = label
        self._isOn = isOn
        self.disabled = disabled
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            DomyText(label, .body)
        }
        .tint(C.accent)
        .disabled(disabled)
        .padding(.vertical, T.Space.s2)
        .frame(minHeight: T.Size.row)
    }
}

/// 設定列：產品色膠囊（Soft 底＋Strong 字），點了開選單。menu 裡放 Button
struct PickerRow<MenuItems: View>: View {
    let label: String
    let value: String
    @ViewBuilder var menu: MenuItems

    init(_ label: String, value: String, @ViewBuilder menu: () -> MenuItems) {
        self.label = label
        self.value = value
        self.menu = menu()
    }

    var body: some View {
        HStack(spacing: T.Space.s3) {
            DomyText(label, .body).fillLeading()
            Menu {
                menu
            } label: {
                HStack(spacing: T.Space.s2) {
                    DomyText(value, .callout, tone: .strong, lines: 1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(T.TypeScale.caption.font)
                        .foregroundStyle(C.strong)
                }
                .padding(.horizontal, T.Space.s3)
                .frame(height: T.Size.pickerHeight)
                .background(C.soft, in: Capsule())
                .frame(minHeight: T.Size.touch)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("\(label)：\(value)")
            .accessibilityHint("點兩下更改")
        }
        .padding(.vertical, T.Space.s2)
        .frame(minHeight: T.Size.row)
    }
}

/// 內容列：上面一行次要資訊（日期、時長），下面是內容，最多兩行
struct DomyListRow: View {
    var meta: String?
    let title: String
    var lines: Int = 2
    var selected: Bool = false
    var action: (() -> Void)?

    init(meta: String? = nil, title: String, lines: Int = 2, selected: Bool = false, action: (() -> Void)? = nil) {
        self.meta = meta
        self.title = title
        self.lines = lines
        self.selected = selected
        self.action = action
    }

    private var row: some View {
        HStack(spacing: T.Space.s3) {
            VStack(alignment: .leading, spacing: T.Space.s1) {
                if let meta {
                    DomyText(meta, .footnote, tone: .secondary)
                }
                DomyText(title, .body, lines: lines)
            }
            .fillLeading()
            if action != nil {
                Chevron()
            }
        }
        .padding(.vertical, T.Space.s3)
        .frame(minHeight: T.Size.row)
        .padding(.horizontal, T.Space.s4)
        .contentShape(Rectangle())
    }

    var body: some View {
        Group {
            if let action {
                Button(action: action) { row }
                    .buttonStyle(RowPressStyle(selected: selected))
            } else {
                row.background(selected ? C.soft : Color.clear)
            }
        }
        .padding(.horizontal, -T.Space.s4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(meta.map { "\(title)，\($0)" } ?? title)
        .accessibilityAddTraits(action == nil ? [] : .isButton)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 有標籤的輸入框。標籤一定在框外，不拿 placeholder 當標籤。
/// error 有值時框變紅、下方顯示紅字＋圖示；錯誤訊息要說清楚怎麼改。
struct DomyTextField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var helper: String?
    var error: String?
    var keyboard: UIKeyboardType = .default
    var multiline: Bool = false
    var submitLabel: SubmitLabel = .done
    var onSubmit: (() -> Void)?
    @FocusState private var focused: Bool

    init(
        _ label: String,
        text: Binding<String>,
        placeholder: String = "",
        helper: String? = nil,
        error: String? = nil,
        keyboard: UIKeyboardType = .default,
        multiline: Bool = false,
        submitLabel: SubmitLabel = .done,
        onSubmit: (() -> Void)? = nil
    ) {
        self.label = label
        self._text = text
        self.placeholder = placeholder
        self.helper = helper
        self.error = error
        self.keyboard = keyboard
        self.multiline = multiline
        self.submitLabel = submitLabel
        self.onSubmit = onSubmit
    }

    var body: some View {
        let border: Color = error != nil ? C.destructive : (focused ? C.accent : C.fieldBorder)
        let width: CGFloat = (error != nil || focused) ? T.Size.hairline * 1.5 : T.Size.hairline
        VStack(alignment: .leading, spacing: T.Space.s2) {
            DomyText(label, .subheadline, weight: .semibold)
            TextField(
                "", text: $text,
                prompt: Text(placeholder).foregroundStyle(C.textSecondary),
                axis: multiline ? .vertical : .horizontal
            )
            .font(T.TypeScale.body.font)
            .foregroundStyle(C.textPrimary)
            .tint(C.accent)
            .keyboardType(keyboard)
            .submitLabel(submitLabel)
            .focused($focused)
            .onSubmit { onSubmit?() }
            .padding(.horizontal, T.Space.s4)
            .padding(.vertical, T.Space.s3)
            .frame(minHeight: T.Size.field)
            .background(C.surface, in: RoundedRectangle(cornerRadius: T.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: T.Radius.md, style: .continuous)
                    .strokeBorder(border, lineWidth: width)
            )
            .accessibilityLabel(label)
            .accessibilityHint(error ?? helper ?? "")
            if let error {
                HStack(spacing: T.Space.s2) {
                    Image(systemName: "exclamationmark.circle")
                        .font(T.TypeScale.footnote.font)
                        .foregroundStyle(C.destructive)
                        .accessibilityHidden(true)
                    DomyText(error, .footnote, tone: .destructive).fillLeading()
                }
            } else if let helper {
                DomyText(helper, .footnote, tone: .secondary)
            }
        }
    }
}

/// 空狀態：說清楚「這裡會出現什麼」和「下一步按哪裡」，一顆按鈕直接帶過去。icon 是 SVG path
struct DomyEmptyState: View {
    var icon: String?
    let title: String
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?

    init(
        icon: String? = nil,
        title: String,
        message: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: T.Space.s3) {
            if let icon {
                LineIcon(icon, color: C.accent)
                    .frame(width: T.Size.emptyIcon, height: T.Size.emptyIcon)
                    .background(C.soft, in: Circle())
            }
            DomyText(title, .title3, align: .center)
            if let message {
                DomyText(message, .subheadline, tone: .secondary, align: .center)
            }
            if let actionTitle, let action {
                DomyButton(actionTitle, size: .compact, action: action)
                    .padding(.top, T.Space.s1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, T.Space.s8)
        .padding(.horizontal, T.Space.s6)
    }
}
