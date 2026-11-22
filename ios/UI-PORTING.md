# 畫面從 React Native 搬到 SwiftUI 的共同規矩

先讀 `ios/PORTING.md`（沒有編譯器時的寫法、不准做的事都在那裡），這份只講畫面。

目標：**長相、文字、流程跟 `mobile/` 一樣**。畫面上每一個中文字照搬，一個字都不改；每一顆按鈕、每一個判斷（什麼時候顯示、什麼時候停用）都要搬。不要加新功能，不要「順便改善」。

## 一定要先讀的檔（都在 `ios/Radish/`）

| 檔 | 內容 |
|---|---|
| `Kit/DomyTokens.swift`、`Kit/Theme.swift` | `T`（尺寸、圓角、間距、字級）和 `C`（顏色）。 |
| `Kit/DomyBasics.swift` | `DomyText`、`DomyButton`、`DomyIconButton`、`Hairline`、`PressStyle`、`Haptic`、`.fillLeading()` |
| `Kit/DomyRows.swift` | `DomySection`、`SettingsRow`、`ToggleRow`、`PickerRow`、`DomyListRow`、`DomyTextField`、`DomyEmptyState`、`Chevron` |
| `Kit/LocalKit.swift` | `Card`、`Segmented`、`Chip`、`ChipRow`、`Tag`、`TagRow`、`Banner`、`CheckRow`、`FieldLabel`、`TextRow`、`FlowLayout` |
| `Kit/Scaffold.swift` | `Screen`（分頁外框）、`SheetScaffold`（彈出卡外框）、`tabBarClearance`、`NoticeBar` |
| `Kit/Icons.swift` | `LineIcon`、`IconPaths`、`CatIcon`、`kindName` |
| `Kit/RadishShape.swift`、`Kit/RadishBuddy.swift` | `Radish`（蘿蔔）、`RadishBuddy`（蘿蔔人）、`svgPath` |
| `App/AppStore.swift` | 狀態與存檔 |
| `App/Sheets.swift` | 彈出卡總管 `Sheets`、`SheetReq`、`AlbumSource` |
| `App/RadishApp.swift` | 外殼、`TabKey`、`PrepStage` |
| `IO/Photos.swift` | `PhotoStore`、`PhotoStrip`、`PhotoThumb`、`PhotoAddButton` |
| `IO/System.swift` | `askReminders`、`syncReminders`、`openNaver/openGoogle/openApple`、`ShareSheet`、`ShareItem` |

規則函式在 `ios/RadishCore/Sources/RadishCore/*.swift`，**要呼叫哪個函式就打開那個 Swift 檔看它真正的簽名**，不要照 TS 猜。跟 app 同一個模組，不用 import。

## RN → SwiftUI 對照

| mobile（RN） | ios（SwiftUI） |
|---|---|
| `const { s, act, say, undo, phase, today, setSettings } = useApp()` | `@Environment(AppStore.self) private var store`，讀 `store.s`、`store.phase`、`store.today`、`store.canUndo` |
| `act((d) => { ...; return '訊息' }, { undoable: true })` | `store.act(undoable: true) { d in ...; return "訊息" }`（closure 是 `(inout AppState) -> String?`，每條路都要 return，沒有訊息就 `return nil`） |
| `act((d) => { 改東西 })`（沒回傳） | `store.mutate { d in 改東西 }`；要能復原就 `store.mutate(undoable: true) { ... }` |
| `setSettings({ pace: 'slow' })` | `store.setSettings { st in st.pace = .slow }` |
| `say('一句話')` | `store.say("一句話")` |
| `const { open, close } = useSheets()`、`open({ kind: 'stop', id })` | `@Environment(Sheets.self) private var sheets`、`sheets.open(.stop(id: id))`、`sheets.close()` |
| 彈出卡的 `onClose` 屬性 | 沒有這個屬性了。卡自己拿 `sheets`，要關就 `sheets.close()` |
| `<Sheet visible title="…" onClose={onClose}>…</Sheet>` | `SheetScaffold("…", onClose: { sheets.close() }) { … }`；`scroll={false}` → `scroll: false` |
| `<Screen title="…" bottomInset={…}>…</Screen>`、`<DomyScreen title>` | `Screen("…") { … }`（底部留白已經內建） |
| `<DomyText variant="title2" tone="secondary" weight="600" numberOfLines={2}>字</DomyText>` | `DomyText("字", .title2, tone: .secondary, weight: .semibold, lines: 2)` |
| `<DomyText style={{ textAlign: 'center' }}>` | `DomyText("字", align: .center)` |
| `<DomyText style={{ flex: 1 }}>` | `DomyText("字").fillLeading()` |
| `<DomyButton title="好" onPress={f} variant="secondary" size="compact" fullWidth disabled />` | `DomyButton("好", variant: .secondary, size: .compact, disabled: true, fullWidth: true) { f() }` |
| `<DomySection title="…" footer="…">列…</DomySection>` | `DomySection("…", footer: "…") { 列… }`（列之間的分隔線會自己加；`if`、`ForEach` 都可以放） |
| `<DomySettingsRow label value onPress />` | `SettingsRow("label", value: "…") { … }`；沒有 onPress 就不給 closure |
| `<DomySettingsRow label toggle={{ value, onValueChange }} />` | `ToggleRow("label", isOn: Binding(get: { … }, set: { v in … }))` |
| `<DomySettingsRow label picker={{ value, onPress }} />`（按了跳選單或輪下一個） | `PickerRow("label", value: "…") { Button("選項") { … } … }`；如果 TS 是「按一下輪到下一個」，選單裡列出全部選項讓人直接選 |
| `<DomyListRow meta title onPress />` | `DomyListRow(meta: "…", title: "…") { … }` |
| `<DomyTextField label value onChangeText placeholder helper error multiline keyboardType="number-pad" />` | `DomyTextField("label", text: $text, placeholder: "…", helper: "…", error: nil, keyboard: .numberPad, multiline: true)` |
| `<DomyEmptyState title body action={{title,onPress}} icon />` | `DomyEmptyState(icon: IconPaths.sprout, title: "…", message: "…", actionTitle: "…") { … }` |
| `<DomyIconButton title="關閉" label="關閉" tone="neutral" />` | `DomyIconButton(title: "關閉", label: "關閉", neutral: true) { … }` |
| `<Card tone="tint">…</Card>` | `Card(tone: .tint) { … }`（裡面已經是直向、間距 s3） |
| `<Segmented value options={[['a','甲'],…]} onChange />` | `Segmented(value: x, options: [(.a, "甲"), …]) { x = $0 }` |
| `<Chip label selected onPress onSurface disabled />` | `Chip("label", selected: true, onSurface: true) { … }` |
| `<ChipRow>`、`<TagRow>`、`<Tag label tone="accent" />` | `ChipRow { … }`、`TagRow { … }`、`Tag("label", tone: .accent)` |
| `<Banner text action={{title,onPress}} />` | `Banner("text", actionTitle: "…") { … }` |
| `<CheckRow checked title note onPress />` | `CheckRow(checked: b, title: "…", note: "…") { … }` |
| `<Label>字</Label>` | `FieldLabel("字")` |
| `<TextRow title note right={…} />` | `TextRow("title", note: "…") { 右邊的東西 }`；沒有右邊就 `TextRow("title", note: "…")` |
| `<CatIcon it={it} />`、`kindName(it)` | `CatIcon(it)`、`kindName(it)`（吃 `Stop`、`BasketItem`、`Place`） |
| `<Radish size="L" scale={2} faded />` | `Radish(size: .L, scale: 2, faded: true)` |
| `<View style={{ flexDirection: 'row', gap: T.space[2] }}>` | `HStack(spacing: T.Space.s2) { … }` |
| `<View style={{ gap: T.space[3] }}>` | `VStack(alignment: .leading, spacing: T.Space.s3) { … }` |
| `T.space[4]`、`T.radius.xl`、`T.size.row`、`T.motion.transition` | `T.Space.s4`、`T.Radius.xl`、`T.Size.row`、`T.Motion.transition` |
| `c.accent`、`c.surface`、`c.textSecondary` | `C.accent`、`C.surface`、`C.textSecondary` |
| `Alert.alert('標題', '內容', [按鈕…])` | `.alert("標題", isPresented: $flag) { Button("…", role: .destructive) { … }; Button("取消", role: .cancel) {} } message: { Text("內容") }`；選項多的用 `.confirmationDialog` |
| `Haptics.selectionAsync()`、`impactAsync(Medium)`、`notificationAsync(Success)` | `Haptic.select()`、`Haptic.impact(.medium)`、`Haptic.notify(.success)` |
| `photoUri(ref)` + `<Image>` | `PhotoThumb(ref: ref, edge: …)` 或 `PhotoStore.image(ref)` |
| `pickPhoto()` | `PhotoAddButton("加照片", disabled: …, onPicked: { name in … }, onFailed: { … })` |
| `removePhotoFile(ref)`、`photoDataUri(ref)`、`writeTemp(name, text)`、`PHOTO_MAX` | `PhotoStore.remove(ref)`、`PhotoStore.dataUri(ref)`、`PhotoStore.writeTemp(name, text)`、`PhotoStore.max` |
| `Share.share({ message })`、`Sharing.shareAsync(uri)` | `@State var share: ShareItem?` ＋ `.sheet(item: $share) { ShareSheet(items: $0.items) }`，設 `share = ShareItem(items: ["字"])` 或 `[url]` |
| `Clipboard.setStringAsync(text)` | `UIPasteboard.general.string = text`（要 `import UIKit`） |
| `useEffect(() => {...}, [x])` | `.onChange(of: x) { _, new in … }`；只跑一次的用 `.task { … }` 或 `.onAppear` |
| `useState` | `@State private var` |
| `useMemo` | 直接寫成算出來的屬性或 body 裡的 `let` |

## 畫面之間講好的名字（不能改，別人會照這個呼叫）

```swift
// Screens/
// 2026-11-23 照線框 A 版改過外殼：三個分頁、推進頁走 Nav（App/Nav.swift 的 Push），半頁走 Sheets（App/Sheets.swift 的 SheetReq）
struct TripScreen: View   { init() }                        // 這趟分頁；最下面 .talkBar
struct StartTrip: View    { init(goSettings: @escaping () -> Void) }
struct AskScreen: View    { init() }                        // 問 AI 分頁
struct TripsScreen: View  { init(goTrip: @escaping () -> Void) }
// 推進頁（nav.push）
struct CheckScreen: View  { init() }                        // 檢查這趟
struct NotesScreen: View  { init() }                        // 須知
struct CostScreen: View   { init() }                        // 花費
struct MeScreen: View     { init() }                        // 平常的我
struct StopScreen: View   { init(id: String) }              // 一站
struct VisitedScreen: View { init(source: AlbumSource) }    // 去過的那一趟

// 半頁（sheets.open，都不帶 onClose，自己用 sheets.close()）
struct ReplySheet: View        { init() }                   // 剛剛那一則
struct MapSheet: View          { init(day: Int) }           // 這一天的路線
struct NearbySheet: View       { init(day: Int) }           // 附近還有什麼
struct MoveSheet: View         { init(id: String) }         // 移到別的時段
struct AddSheet: View          { init() }
struct TripSettingsSheet: View { init() }
struct MoreSheet: View         { init(day: Int) }

// Components/
struct TripFormValue { … }                                    // 欄位照 TS 的 TripFormValue
func blankForm() -> TripFormValue
func formOf(_ t: Trip) -> TripFormValue
func missingOf(_ v: TripFormValue) -> [String]
struct TripForm: View     { init(value: Binding<TripFormValue>, minStart: String, fallbackBase: BaseKey) }
struct CalendarGrid: View { init(min: String, value: String?, onPick: @escaping (String) -> Void) }   // TS 的 Calendar（Foundation 已經有 Calendar，所以改名）
struct PullMoment: View   { init(name: String, size: StopSize, line: String, onDone: @escaping () -> Void) }
struct VisitNote: View    { init(say: String?, photos: [String], onSay: @escaping (String) -> Void, onPhotos: @escaping ([String]) -> Void) }
struct AllergyCardView: View { init(list: [String]) }          // TS 的 AllergyCard 元件（RadishCore 裡已經有同名的資料型別 AllergyCard）
struct MapPoint: Identifiable { … }                             // 欄位照 TS，key 當 id
struct DayMap: View       { init(points: [MapPoint]) }
```

## 寫 SwiftUI 時特別要注意

- **不准寫色碼和數字**：顏色用 `C`，尺寸、間距、圓角、字級用 `T`。CI 會跑 `ios/tools/check-hardcoded.mjs` 擋。真的只用一次的數值（例如動畫的幾何），那一行結尾寫 `// domy-ignore: 原因`。TS 裡原本有 `// domy-ignore` 的地方照搬。
- 所有字都用 `DomyText`，不要直接用 `Text(...).font(...)`。
- `body` 太長編譯器會算不出型別（「unable to type-check this expression in reasonable time」）。**一個 `body` 或一個 `@ViewBuilder` 函式不要超過大約 40 行**，把每個區塊拆成 `private var xxxSection: some View` 或 `@ViewBuilder private func xxx(...) -> some View`。TS 檔裡的每個子元件（function）在 Swift 也各寫成一個 `private struct … : View`。
- `ForEach` 一定要給穩定的 id：`ForEach(items, id: \.id)`；沒有 id 的用 `ForEach(Array(list.enumerated()), id: \.offset) { index, item in … }`。
- `if let x = …` 可以放在 ViewBuilder 裡；但 `guard`、`for`、指定敘述（`x = 1`）不行，計算先放在 `let` 或另外的函式。
- 讀狀態一律從 `store.s` 現讀，不要把 `store.s.trip` 複製到 `@State` 裡留著（會過期）。只有表單正在輸入的草稿才用 `@State`。
- 在 closure 裡改 store：`store.act { d in … }` 的 `d` 是 `inout AppState`；要改行程寫 `guard var trip = d.trip else { return nil }` → 改 `trip` → `d.trip = trip`，或直接 `moveItem(&d.trip!, …)` **不行（不准用 `!`）**，照前面那種寫。呼叫規則函式要傳兩個 inout（`&trip, &d.seeds`）時，先 `var trip = …`、`var seeds = d.seeds`，呼叫完再寫回去。
- 無障礙：TS 裡的 `accessibilityLabel`、`accessibilityRole="header"`（→ `.accessibilityAddTraits(.isHeader)`）照搬。主要按鈕和列加 `.accessibilityIdentifier("…")` 方便 UI 測試找（用英文短名，例如 `"start-go"`、`"stop-pull"`）。
- 鍵盤：輸入框在 `ScrollView` 裡 SwiftUI 會自己避開鍵盤，不用另外處理。
- 這個 app 最低 iOS 18，可以用 iOS 17、18 的 API（`@Observable`、`onChange(of:) { old, new in }`、`MapKit` 的新 `Map { Marker(…) }`、`.sensoryFeedback`）。專案用 Swift 5 語言模式。
- 每個檔案開頭用一兩行中文註解說這個檔在做什麼，並寫上對應的 mobile 檔路徑。TS 裡原本的註解照搬。

## 產品鐵則（搬的時候不准弄丟）

- 會改行程的動作都要能復原：TS 裡有 `{ undoable: true }` 的地方，Swift 一定要 `undoable: true`。
- 估的寫估的、AI 加的寫 AI 加的、沒核對的標沒核對：這些字在 TS 畫面上都有，照搬。
- 不做連續天數、稀有蘿蔔、排行榜。
