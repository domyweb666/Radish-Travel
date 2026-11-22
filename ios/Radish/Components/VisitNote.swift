// 去過的一站可以留的東西：一句話、幾張照片。旅途中的站和已經收起來的旅行共用這一塊。
// 對應 mobile/src/components/VisitNote.tsx。一站改成推進頁（Screens/StopScreen.swift）後也是放在那一頁裡。
import SwiftUI

struct VisitNote: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    let photos: [String]
    let onSay: (String) -> Void
    let onPhotos: ([String]) -> Void
    // 打到一半就按「好了」或「關閉」時，輸入框不一定來得及說它打完了。所以關掉這一塊的時候再存一次，打的字才不會不見。
    @State private var typed: String
    @State private var saved: String

    private static let sayMax: Int = 60

    init(
        say: String?,
        photos: [String],
        onSay: @escaping (String) -> Void,
        onPhotos: @escaping ([String]) -> Void
    ) {
        self.photos = photos
        self.onSay = onSay
        self.onPhotos = onPhotos
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
        photoCard
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
        .onDisappear { commit() }
        // 打到一半就切走 app 或被系統結束：離開前台的那一下先存起來（S06「那一句打到一半被結束」）
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                commit()
            }
        }
        .accessibilityIdentifier("visit-say")
    }

    private var photoCard: some View {
        let full: Bool = photos.count >= PhotoStore.max
        return Card {
            FieldLabel("照片")
            PhotoStrip(
                refs: photos,
                onRemove: { (ref: String) in
                    onPhotos(photos.filter { (p: String) -> Bool in p != ref })
                    PhotoStore.remove(ref)
                })
            PhotoAddButton(
                full ? "最多 \(PhotoStore.max) 張" : "從相簿加一張",
                disabled: full,
                onPicked: { (name: String) in
                    onPhotos(photos + [name])
                },
                onFailed: {
                    store.say("這張照片加不進來，換一張試試。")
                }
            )
            .accessibilityIdentifier("visit-add-photo")
            DomyText("照片會縮小後存在這支手機裡，沒網路也看得到。不會上傳到任何地方。", .footnote, tone: .secondary)
        }
    }
}
