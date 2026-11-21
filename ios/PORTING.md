# 從 mobile/（TypeScript）搬到 ios/（Swift）的共同規矩

這台電腦沒有 Swift 編譯器，寫完只能推上 GitHub Actions 才知道編不編得過。所以寫法要保守，大家照同一套規矩，彼此才接得起來。

## 檔案放哪

- `ios/RadishCore/Sources/RadishCore/`：資料型別、規則、純計算。**只准 `import Foundation`**（要在 Linux 上跑測試）。不准 SwiftUI、UIKit、CoreLocation、CoreGraphics。
- `ios/RadishCore/Tests/RadishCoreTests/`：XCTest。`@testable import RadishCore`。
- `ios/Radish/`：app 本體（SwiftUI）。RadishCore 的原始碼是直接編進 app 的，同一個模組，**不用 import RadishCore，也不用寫 public**。

## 已經寫好、可以直接用的

- `Models.swift`：全部資料型別。TS 的 `Size` 叫 `StopSize`，`Body` 叫 `BodyLimit`，`Pick`（吃與買）叫 `Tip`。`Stop.a` 是 `AreaKey?`（TS 的空字串等於 nil）。金額一律 `Double`，天數人數 `Int`。TS 裡 `b?: boolean` 這種在 Swift 是 `Bool?`，判斷寫 `x.b == true`。`Settings.queue` 的三個值是 `.no`、`.few`（存 "some"）、`.all`（存 "any"）。
- `SeoulData.swift`：全域常數，名字跟 TS 一樣（`AREA`、`ADJ`、`HOTEL`、`PLACES`、`CAT`、`FOOD`、`FLV`、`AVOID`、`MEH`、`ALLERGENS`、`PURPOSE`、`PART`、`PULL_LINES`、`STAY`、`TABOO`、`TABOO_LEVEL`、`DIFF`、`CHECKLIST`、`NO_BRING`、`SOS`、`EATS`、`DISHES`、`GIFTS`、`GIFT_RULES`）。字典查值用 `AREA[need: .A]`（一定有值）或 `AREA[key]`（Optional）。

## 函式怎麼搬

1. **名字跟 TS 一樣**，寫成檔案最外層的自由函式（不要包進 enum 或 struct）。
2. **參數照 TS 的順序，全部不加外部標籤**：`func moveItem(_ t: inout Trip, _ id: String, _ day: Int, _ part: Part) -> String?`，呼叫是 `moveItem(&t, id, day, part)`。
3. TS 裡會直接改到傳進來的物件的（`t`、`seeds`、`d`、`st`），Swift 用 `inout`。只讀的就一般參數。
4. TS 回 `string | null` → `String?`；回 `string | undefined` → `String?`；`void` 就沒有回傳。
5. TS 的預設參數照樣給預設值。亂數參數 `rnd: () => number` → `_ rnd: () -> Double = { Double.random(in: 0..<1) }`。
6. `Pick<Trip, 'base'> | null` 這種只拿幾個欄位的，Swift 直接收整個型別（`Trip?`）。真的要同時吃兩種型別（例如 `Stop` 和 `Place`、`BasketItem`）就寫兩個同名多載。
7. 模組最外層的常數名字照 TS（`PARTS`、`LOCAL_HINTS`、`WALK_TEXT`…）。`Record<K, {name, note}>` 這種用小 struct 裝，字典用 enum 當鍵。
8. TS 的 union 字面值（`'hot' | 'cold' | null`）寫成 `String` raw value 的 enum，case 名字就是那個字。

### Plan.swift 已經講定的形狀（別的檔會用到，不能改）

```swift
/// TS 的 { it, s }：一站和它所在的時段。si、ii 是在 t.slots 和 slots[si].items 裡的位置，要改就用位置去改
struct Found { let it: Stop; let s: Slot; let si: Int; let ii: Int }

let PARTS: [Part]
func defaultSettings() -> Settings
func money(_ n: Double) -> String
func newId(_ prefix: String) -> String
func generate(_ d: TripDraft, _ base0: Settings, _ shuffle: Bool = false, _ rnd: () -> Double = { Double.random(in: 0..<1) }) -> Trip
func allItems(_ t: Trip) -> [Found]
func usedIds(_ t: Trip) -> Set<String>
func halfDays(_ t: Trip) -> Int
func findItem(_ t: Trip, _ id: String) -> Found?
func slotAt(_ t: Trip, _ day: Int, _ part: Part) -> Int?      // 回 t.slots 的位置
func bigCount(_ t: Trip, _ day: Int) -> Int
func areaOf(_ it: Stop) -> String
func dayStops(_ t: Trip, _ day: Int) -> [Found]
func warnings(_ t: Trip) -> [String]
func moveItem(_ t: inout Trip, _ id: String, _ day: Int, _ part: Part) -> String?
func swapParts(_ t: inout Trip, _ day: Int, _ a: Part, _ b: Part) -> String?
func swapDays(_ t: inout Trip, _ a: Int, _ b: Int) -> String?
func seedOut(_ t: inout Trip, _ seeds: inout [Seed], _ id: String, _ why: String) -> Stop?
func restoreSeed(_ t: inout Trip, _ seeds: inout [Seed], _ seedId: String) -> String
func addOwn(_ t: inout Trip, _ seeds: inout [Seed], _ name: String) -> String
func alternatives(_ t: Trip, _ base: Settings, _ it: Stop) -> [Place]
func replaceWith(_ t: inout Trip, _ fromId: String, _ p: Place) -> String?
func nearbyPool(_ t: Trip, _ day: Int, _ st: Settings? = nil) -> [String]
func baseOf(_ t: Trip?, _ st: Settings) -> BaseKey
func hotelPt(_ st: Settings, _ t: Trip? = nil) -> HotelPt
func draftOf(_ t: Trip) -> TripDraft
func cost(_ t: Trip, _ base: Settings) -> (rows: [CostRow], total: Double, people: Int)
func planText(_ t: Trip, _ withIds: Bool = false, _ fmtDate: ((Int) -> String)? = nil) -> String
```

### Dates.swift 已經講定的形狀

```swift
enum Phase: Equatable { case plan(daysToGo: Int); case trip(day: Int); case done }
func todayISO(_ now: Date = Date()) -> String
func addDays(_ iso: String, _ n: Int) -> String
func diffDays(_ a: String, _ b: String) -> Int
func weekday(_ iso: String) -> String
func fmtDay(_ iso: String) -> String
func monthGrid(_ year: Int, _ month: Int) -> [String?]
func phaseOf(_ start: String, _ days: Int, _ today: String, _ debugDay: Int?) -> Phase
```

### Prefs.swift 已經講定的形狀

```swift
func tripSettings(_ st: Settings, _ tweaks: [Tweak]?) -> Settings
func banned(_ p: Place, _ st: Settings) -> Bool      // Stop 也要一個多載
```

## 沒有編譯器時的寫法

- 型別寫清楚，不要靠推斷：`let rows: [CostRow] = ...`、closure 參數和回傳型別寫出來。
- 一個運算式不要太長。`a.filter{}.map{}.reduce` 串三層以上就拆成幾行、各給型別，不然編譯器會說「運算式太複雜」。
- 數字型別不會自動轉：`Int` 和 `Double` 混算要自己寫 `Double(x)`。`Math.round(x)` → `x.rounded()`（回 Double），要 Int 再 `Int(...)`。
- 不要用 `!` 強制解包，用 `guard let`、`if let`、`??`。
- struct 是值：`var it = t.slots[si].items[ii]` 是複製一份，改了要寫回 `t.slots[si].items[ii] = it`。這是從 TS 搬過來最容易錯的地方，每個會改資料的函式都要檢查。
- 字串切片麻煩，能用 `hasPrefix`、`contains`、`components(separatedBy:)`、`replacingOccurrences` 就用。正規表示式用 `NSRegularExpression`（Linux 也有）；不要用 Swift 的 regex 字面值 `/.../`。
- `toLocaleString('en-US')`（千分位）自己寫一個小函式，不要用 `NumberFormatter`（Linux 上行為不一樣）。
- `toFixed(1)` → `String(format: "%.1f", x)`。
- 日期用 UTC 的 `Calendar(identifier: .gregorian)` 自己算，不要靠裝置時區（`todayISO` 例外，它要的是裝置當地的今天）。
- `JSON.parse(JSON.stringify(x))`（深複製）在 Swift 不用做，struct 指定就是複製。
- 排序：TS 的 `sort` 是穩定的，Swift 的 `sort` 不保證。規則靠排序結果的地方，比較時把原本的位置當第二個鍵。
- 每個檔案開頭用一兩行中文註解說這個檔在做什麼；TS 裡原本的註解照搬。

## 測試

- XCTest，一個 TS 測試檔對一個 Swift 檔（`plan.test.ts` → `PlanTests.swift`）。
- TS 的每一個 `test('…')` 都要有一個對應的 `func test…()`，中文名字可以直接當函式名（空白和標點換成底線，數字不能在最前面）。裡面的每個斷言都要搬，不要偷少。
- 固定亂數的地方照 TS 測試的做法。

## 不准做的事

- 不准動別人負責的檔，不准動 `mobile/`、`prototype/`。
- 不准 `git add`、`git commit`、`git push`、切分支。寫完回報就好。
- 不准開 worktree，就在 `E:\蘿蔔旅行` 裡做。
