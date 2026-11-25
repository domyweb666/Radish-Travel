// 這趟分頁最上面的兩張卡：剛排好那張（S01 第一次，線框 .uiux/03-線框/線框/A4-Planned.dc.html）、
// 回來後那張（S01 回來後，線框 A9-Done.dc.html）。TripScreen 決定放在哪，卡自己決定要不要出現。
import SwiftUI

/* ---------- 剛排好那張 ---------- */

/// 這次開 app 已經出現過的剛排好那張卡（記的是 planMarkOf）。
/// 關掉 app 再開就清空：剛排好那張卡只在排好之後第一次看到的那段時間出現
@MainActor
enum PlannedSeen {
    static var marks: Set<String> = []

    /// 這一版還是排好的樣子、那張卡該不該在。跟 AI 講的 talkFinish 也用：開一趟時寫的那句改完，卡要留著
    static func fresh(_ trip: Trip) -> Bool {
        if let saved = trip.planMark {
            return saved == planMarkOf(trip) && marks.contains(saved)
        }
        // 還沒記過：剛排好的，或更新前就排好的舊行程。舊行程動過的就不出現
        return planUntouched(trip)
    }
}

/// 寫這一版是誰排的、照你說的排了哪些、開一趟時寫的那句現在怎樣（AI 照它改了哪些，或還沒送），右上角「不要這一版」（可以復原，回到開一趟）。
/// 只在出發前、這一版還沒動過時出現；改過一站、關掉 app 再開，就不出現了
struct PlannedCard: View {
    @Environment(AppStore.self) private var store
    private let trip: Trip

    init(trip: Trip) {
        self.trip = trip
    }

    private var visible: Bool {
        let phase: Phase = phaseOf(trip.start, trip.days, store.today, store.s.debugDay)
        guard case .plan = phase else { return false }
        return PlannedSeen.fresh(trip)
    }

    var body: some View {
        if visible {
            card
                .onAppear { remember() }
        }
    }

    private var card: some View {
        let text: PlanCardText = planCardText(trip, store.s.settings, store.s.chat, store.talkBusy)
        return Card {
            HStack(alignment: .center, spacing: T.Space.s2) {
                DomyText(text.head, .footnote, tone: .secondary)
                    .fillLeading()
                DomyButton("不要這一版", variant: .plain, size: .compact) {
                    drop()
                }
                // 高度只縮按鈕的：左邊的字換行時，上下才不會貼到卡邊和下面那段
                .padding(.vertical, -T.Space.s2)
                .padding(.trailing, -T.Space.s4)
                .accessibilityIdentifier("planned-drop")
            }
            DomyText(text.body, .subheadline)
            if let wish = text.wish {
                DomyText(wish, .subheadline)
                    .accessibilityIdentifier("planned-wish")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("這一版怎麼排的")
        .accessibilityIdentifier("planned-card")
    }

    /// 第一次出現：記下這一版的樣子。之後算出來對不上，就是改過了
    private func remember() {
        if trip.planMark != nil { return }
        let mark: String = planMarkOf(trip)
        PlannedSeen.marks.insert(mark)
        store.mutate { (d: inout AppState) -> Void in
            guard var t = d.trip else { return }
            t.planMark = mark
            d.trip = t
        }
    }

    private func drop() {
        Haptic.select()
        store.act(undoable: true) { (d: inout AppState) -> String? in
            return dropPlan(&d)
        }
    }
}

/* ---------- 回來後那張 ---------- */

/// 這趟走完了：去了幾個地方，看這趟去過的地方（推進），做成地圖網頁傳給朋友。
/// 「收起來，開新的一趟」放在卡片外面，可以復原。只在 phase == .done 時放進來
struct DoneCard: View {
    @Environment(AppStore.self) private var store
    @Environment(Nav.self) private var nav
    @State private var busy: Bool = false
    @State private var share: ShareItem? = nil
    private let trip: Trip

    init(trip: Trip) {
        self.trip = trip
    }

    var body: some View {
        let pulled: Int = visitedOf(trip).count
        VStack(alignment: .leading, spacing: T.Space.s1) {
            Card {
                VStack(alignment: .leading, spacing: T.Space.s1) {
                    DomyText("這趟走完了", .title2)
                        .accessibilityAddTraits(.isHeader)
                    DomyText(countLine(pulled), .subheadline, tone: .secondary)
                }
                if pulled > 0 {
                    actions
                }
            }
            archiveLink
        }
        .sheet(item: $share) { (item: ShareItem) in
            ShareSheet(items: item.items)
        }
    }

    private func countLine(_ pulled: Int) -> String {
        if pulled > 0 { return "這趟去了 \(pulled) 個地方。" }
        return "這趟沒有按過「去過了」的站。有去過但沒按到的，點那一站可以補。"
    }

    private var actions: some View {
        VStack(spacing: T.Space.s2) {
            DomyButton("看這趟去過的地方", fullWidth: true) {
                nav.push(.visited(.current))
            }
            .accessibilityIdentifier("done-visited")
            DomyButton(
                busy ? "正在做網頁檔…" : "做成地圖網頁，傳給朋友", variant: .secondary, disabled: busy, fullWidth: true
            ) {
                makeShare()
            }
            .accessibilityIdentifier("done-share")
        }
    }

    private var archiveLink: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            DomyButton("收起來，開新的一趟", variant: .plain, size: .compact) {
                store.act(undoable: true) { (d: inout AppState) -> String? in
                    return archiveTrip(&d)
                }
            }
            .padding(.trailing, -T.Space.s4)
            .accessibilityIdentifier("trip-archive")
        }
    }

    private func makeShare() {
        if busy { return }
        guard let v = visitedTrip(store.s, .current), !v.items.isEmpty else { return }
        busy = true
        Task { @MainActor in
            let url: URL? = await makeAlbumFile(v)
            busy = false
            if let url {
                share = ShareItem(items: [url])
            } else {
                store.say("網頁檔沒做成功，等一下再試一次。")
            }
        }
    }
}
