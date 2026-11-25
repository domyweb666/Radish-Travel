// 去過的一站可以留的東西：一句話、幾張照片。旅途中的站和已經收起來的旅行共用這一塊。
// 對應 mobile/src/components/VisitNote.tsx。一站改成推進頁（Screens/StopScreen.swift）後也是放在那一頁裡。
// QC-0013 起一站頁的照片去沒去過都能加，放在 StopScreenMine.swift 的 StopPhotoBlock，那一頁只用這裡的那一句（withPhotos: false）。
import Combine
import SwiftUI
import UIKit

struct VisitNote: View {
    @Environment(AppStore.self) private var store
    let say: String?
    let photos: [String]
    let onSay: (String) -> Void
    let onAdd: (String) -> Void
    let onRemove: (String) -> Void
    /// false：只有那一句，照片在別的地方加
    let withPhotos: Bool
    // 打到一半就按「好了」或「關閉」時，輸入框不一定來得及說它打完了。所以關掉這一塊的時候再存一次，打的字才不會不見。
    @State private var typed: String
    @State private var saved: String

    private static let sayMax: Int = 60

    init(
        say: String?,
        photos: [String],
        onSay: @escaping (String) -> Void,
        onAdd: @escaping (String) -> Void,
        onRemove: @escaping (String) -> Void,
        withPhotos: Bool = true
    ) {
        self.say = say
        self.photos = photos
        self.onSay = onSay
        self.onAdd = onAdd
        self.onRemove = onRemove
        self.withPhotos = withPhotos
        self._typed = State(initialValue: say ?? "")
        self._saved = State(initialValue: say ?? "")
    }

    private func commit() {
        let v: String = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if v == saved { return }
        saved = v
        onSay(v)
    }

    var body: some View {
        sayField
        if withPhotos {
            photoCard
        }
    }

    private var sayField: some View {
        DomyTextField(
            "這裡最想講的一件事",
            text: $typed,
            placeholder: "例如：湯比想像中清",
            helper: "一句就好，不寫也可以。會收在「旅行」裡這一趟的去過的。",
            onSubmit: { commit() }
        )
        .onChange(of: typed) { _, new in
            if new.count > VisitNote.sayMax {
                typed = String(new.prefix(VisitNote.sayMax))
            }
        }
        // 打完才存一次，一次算一步。打到一半就切走 app 或被系統結束，也先存起來（S06「那一句打到一半被結束」）
        .onFieldDone { commit() }
        // 按了復原：框裡的字跟著變回去。正在打、還沒存的字不動
        .onChange(of: say ?? "") { (_: String, now: String) in
            if now == saved { return }
            let mine: String = typed.trimmingCharacters(in: .whitespacesAndNewlines)
            if mine == saved {
                typed = now
            }
            saved = now
        }
        .accessibilityIdentifier("visit-say")
    }

    private var photoCard: some View {
        let full: Bool = photos.count >= PhotoStore.max
        return Card {
            FieldLabel("照片")
            PhotoStrip(
                refs: photos,
                onRemove: { (ref: String) in onRemove(ref) })
            PhotoAddButton(
                full ? "最多 \(PhotoStore.max) 張" : "從相簿加一張",
                disabled: full,
                onPicked: { (name: String) in onAdd(name) },
                onFailed: {
                    store.say("這張照片加不進來，換一張試試。")
                }
            )
            .accessibilityIdentifier("visit-add-photo")
            DomyText("照片會縮小後存在這支手機裡，沒網路也看得到。不會上傳到任何地方。", .footnote, tone: .secondary)
        }
    }
}

// MARK: - 輸入框打完了

extension View {
    /// 輸入框打完的時候叫：離開框、收鍵盤、離開這一頁、切走 app。可能連著叫好幾次，裡面要自己看有沒有變
    func onFieldDone(_ action: @escaping () -> Void) -> some View {
        modifier(FieldDone(action: action))
    }
}

private struct FieldDone: ViewModifier {
    let action: () -> Void
    @Environment(\.scenePhase) private var scenePhase

    // 有 private 的環境值，自動產生的 init 會變成 private，所以自己寫一個
    init(action: @escaping () -> Void) {
        self.action = action
    }

    private var ended: NotificationCenter.Publisher {
        return NotificationCenter.default.publisher(for: UITextField.textDidEndEditingNotification)
    }

    private var hidden: NotificationCenter.Publisher {
        return NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
    }

    func body(content: Content) -> some View {
        content
            // 等這一輪跑完再叫：注音選字還沒確定的字，這時候才會進到框裡
            .onReceive(ended.receive(on: DispatchQueue.main)) { (_: Notification) in action() }
            .onReceive(hidden.receive(on: DispatchQueue.main)) { (_: Notification) in action() }
            .onDisappear { action() }
            .onChange(of: scenePhase) { (_: ScenePhase, phase: ScenePhase) in
                if phase != .active {
                    action()
                }
            }
    }
}
