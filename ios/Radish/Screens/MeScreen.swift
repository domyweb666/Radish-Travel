// 平常的我（從每個分頁右上角推進）：設一次，每趟照這個排；送給 AI 的資料（可以收回）、備份、測試用的開關。
// 主畫面只是一張清單，每列寫著現在的值；點一列才打開那一項來改（那些卡在 MeEditors.swift）。
// 對應 mobile/src/screens/MeScreen.tsx。
import SwiftUI
import UIKit

struct MeScreen: View {
    @Environment(AppStore.self) private var store
    @State private var editing: MeEditing?
    @State private var backup: String = ""
    @State private var importErr: String?
    @State private var aboutBuy: Bool = false

    init() {}

    private var st: Settings { store.s.settings }

    var body: some View {
        Screen("平常的我") {
            usualSection
            learnedSection
            budgetSection
            buyLinksSection
            dataSection
            if let trip = store.s.trip {
                debugSection(trip)
            }
        }
        .sheet(item: $editing, onDismiss: { importErr = nil }) { (kind: MeEditing) in
            MeEditorSheet(kind: kind, backup: $backup, importErr: $importErr, close: { editing = nil })
                .environment(store)
                .tint(C.accent)
        }
    }

    /// 清單上的一列：右邊寫現在的值，點了打開那一項
    private func row(_ label: String, _ value: String?, _ kind: MeEditing) -> some View {
        SettingsRow(label, value: value) {
            editing = kind
        }
        .accessibilityIdentifier("me-row-\(kind.rawValue)")
    }

    /* ---------- 每一列右邊的字 ---------- */

    private var purposeText: String {
        if st.purposes.isEmpty { return "都可以" }
        let names: [String] = st.purposes.map { (k: Purpose) -> String in PURPOSE[need: k] }
        return names.joined(separator: "、")
    }

    private var foodText: String {
        let fp: [FoodKind: Int] = foodPct(st)
        var top: FoodKind = .street
        var best: Int = fp[.street] ?? 0
        for k in FoodKind.allCases {
            let v: Int = fp[k] ?? 0
            if v > best {
                top = k
                best = v
            }
        }
        return "\(FOOD[need: top].name)為主"
    }

    private var eatText: String {
        var parts: [String] = []
        if !st.allergy.isEmpty { parts.append("過敏 \(st.allergy.count) 樣") }
        if !st.avoid.isEmpty { parts.append("不吃 \(st.avoid.count) 樣") }
        if !st.meh.isEmpty { parts.append("不愛 \(st.meh.count) 樣") }
        return parts.isEmpty ? "沒有" : parts.joined(separator: "、")
    }

    private var likesText: String {
        let likes: [Cat] = Cat.allCases.filter { (k: Cat) -> Bool in (st.play[k] ?? 0) != 0 }
        var names: [String] = likes.map { (k: Cat) -> String in CAT[need: k] }
        names.append(contentsOf: st.tags)
        if names.isEmpty { return "都可以" }
        if names.count > 2 { return "\(names[0])等 \(names.count) 種" }
        return names.joined(separator: "、")
    }

    private var bodyText: String {
        if st.body.isEmpty { return "沒有" }
        let names: [String] = st.body.map { (k: BodyLimit) -> String in BODY_TEXT[k] ?? "" }
        return names.joined(separator: "、")
    }

    /* ---------- 區塊 ---------- */

    private var usualSection: some View {
        let tail: String = store.s.trip != nil ? "改了之後，回「這趟」可以照新的重排。" : ""
        return DomySection(footer: "設一次，之後每趟都照這個排。\(tail)") {
            row("旅行回來想怎樣", purposeText, .purposes)
            row("一天排多滿", MeOptions.label(MeOptions.pace, st.pace), .pace)
            row("吃的偏好", foodText, .food)
            row("過敏和不吃的", eatText, .avoid)
            row("喜歡做什麼", likesText, .play)
            row("早上", MeOptions.label(MeOptions.wake, st.wake), .wake)
            row("怎麼移動", MeOptions.label(MeOptions.move, st.move), .move)
            row("一天能走多少", MeOptions.label(MeOptions.walk, st.walk), .walk)
            row("身體上要避開的", bodyText, .body)
            row("住哪一帶", MeOptions.label(MeOptions.base, st.base), .base)
            // QC-0013 #105：從預算那區搬上來，估花費和 AI 推薦旅館都照這個
            row("住宿偏好", MeOptions.label(MeOptions.stays, st.stay), .stay)
        }
    }

    private var learnedSection: some View {
        let value: String = st.learned.isEmpty ? "還沒有" : "\(st.learned.count) 條"
        return DomySection(footer: "你在行程上拿掉一站、選了「以後不排」，會記在這裡。每一條都寫著是哪一次記的。") {
            row("從行程學到的", value, .learned)
        }
    }

    private var budgetSection: some View {
        // 住宿只在上面「住宿偏好」改一個地方；住一晚多少照那裡估
        DomySection("預算", footer: "只拿來估這趟大概花多少，不會影響排哪些站。住一晚多少照上面的「住宿偏好」估。") {
            row("一天吃喝", money(st.budget), .budget)
        }
    }

    /// 排序和連結：有 Klook、KKday 的連結才出現，講一次分潤，連結旁邊不寫
    @ViewBuilder private var buyLinksSection: some View {
        if hasAffiliate(buyLinkTable()) {
            DomySection {
                SettingsRow("排序和連結") {
                    aboutBuy = true
                }
                .accessibilityIdentifier("me-row-buylinks")
            }
            .sheet(isPresented: $aboutBuy) {
                BuyLinksAbout(onClose: { aboutBuy = false })
                    .tint(C.accent)
            }
        }
    }

    private var dataSection: some View {
        DomySection(
            "資料",
            footer: "行程、去過的旅行、照片、設定都只存在這支手機裡，沒有網路也看得到。換手機前先複製備份；備份裡沒有照片，照片要另外留。"
        ) {
            // 填了就直接問 Claude；金鑰存在鑰匙圈，不進備份
            row("Claude API 金鑰", store.claudeKeySet ? maskedClaudeKey(CLAUDE_KEY) : "沒有填", .claude)
            // 開發測試用：連自己電腦的 Claude CLI，有連就先用它
            row("連電腦的 Claude CLI", store.bridgeSet ? maskedBridge(BRIDGE_URL) : "沒有連", .bridge)
            // 線框 A17：寫現在會送去哪裡、那個地方同意了沒。收回之後下次要送給 AI 前會再問一次
            row("送給 AI 的資料", aiText, .ai)
            SettingsRow("複製備份") {
                copyBackup()
            }
            .accessibilityIdentifier("me-row-backup")
            row("貼上備份還原", nil, .importBackup)
            SettingsRow("全部清掉重來", destructive: true) {
                editing = .reset
            }
            .accessibilityIdentifier("me-reset")
        }
    }

    /// 例：Anthropic・已同意。點進去可以收回
    private var aiText: String {
        guard let dest = store.aiDest else {
            return store.s.aiAgreed.isEmpty ? "沒有接 AI" : "沒有接 AI・可以收回"
        }
        let name: String
        switch dest.kind {
        case .bridge: name = "你連的電腦"
        case .key: name = "Anthropic"
        case .server: name = "蘿蔔旅行伺服器"
        }
        return store.aiAgreedHere ? "\(name)・已同意" : "\(name)・還沒同意"
    }

    /// 備份不帶送給 AI 的同意：還原到哪支手機，就由那支手機自己問
    private func copyBackup() {
        var out: AppState = store.s
        revokeAI(&out)
        let data: Data? = try? JSONEncoder().encode(out)
        if let data, let text = String(data: data, encoding: .utf8) {
            UIPasteboard.general.string = text
            store.say("備份複製好了，貼到備忘錄存起來。")
        } else {
            store.say("複製不了，等一下再試一次。")
        }
    }

    /* ---------- 測試用 ---------- */

    private func debugText(_ trip: Trip) -> String {
        guard let day = store.s.debugDay else { return "照日期" }
        return day > trip.days ? "已經回來" : "第 \(day) 天"
    }

    private func setDebug(_ day: Int?) {
        store.mutate { (d: inout AppState) in
            guard d.trip != nil else { return }
            d.debugDay = day
        }
    }

    // TS 是按一下輪到下一個（照日期 → 第 1 天 → … → 已經回來 → 照日期）。這裡把全部選項列在選單裡直接選
    private func debugSection(_ trip: Trip) -> some View {
        let days: [Int] = trip.days >= 1 ? Array(1...trip.days) : []
        return DomySection("測試用", footer: "正式版會照日期自動進入旅途中。這裡讓你出發前先看旅途中的樣子。") {
            PickerRow("假裝現在是", value: debugText(trip)) {
                Button("照日期") { setDebug(nil) }
                ForEach(days, id: \.self) { (day: Int) in
                    Button("第 \(day) 天") { setDebug(day) }
                }
                Button("已經回來") { setDebug(trip.days + 1) }
            }
            .accessibilityIdentifier("me-row-debugDay")
        }
    }
}
