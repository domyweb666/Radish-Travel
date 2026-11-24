// UI 測試用的場景：一開 app 就停在要截圖的那個狀態，不用每次從空白點過去。
// 整個檔包在 #if DEBUG，TestFlight 走 Release，這些不會進去；平常開 app 沒帶參數也不會生效。
// 啟動參數（RadishUITests/SceneUITests.swift 帶的）：
//   -uitest-scene <名字>              寫一份存檔，名字看 state(_:)
//   -uitest-dest bridge|key|endpoint  假裝接了 AI，送去的地方全是假的
//   -uitest-ai ok|fail|slow           假的 AI 怎麼回。沒帶當成 fail。有帶 -uitest-dest 就一定攔下來，不會真的打網路
//   -uitest-agreed                    那個地方當成同意過了
//   -uitest-offline                   假裝沒網路（在 IO/Network.swift）
// 日期都從今天往前往後推，行程用 generate 排，所以資料包或規則改了這裡會跟著變。
#if DEBUG
    import Foundation

    enum UITestScenes {
        /// RadishApp.init 叫，要在 AppStore 建起來之前：存檔、送去哪裡都先放好
        static func prepare(_ args: [String]) {
            if let dest = value("-uitest-dest", args) {
                setDest(dest)
                UITestAIProtocol.mode = value("-uitest-ai", args) ?? "fail"
                _ = URLProtocol.registerClass(UITestAIProtocol.self)
            }
            guard let name = value("-uitest-scene", args), var out = state(name) else { return }
            out.guideSeen = true
            if args.contains("-uitest-agreed"), let dest = aiDestNow() {
                agreeAI(&out, dest)
            }
            write(out)
        }

        /// 參數後面那個字。沒有就是 nil
        private static func value(_ key: String, _ args: [String]) -> String? {
            guard let i = args.firstIndex(of: key), i + 1 < args.count else { return nil }
            return args[i + 1]
        }

        /// 三種都是假的：本機沒有人聽的埠、不是金鑰的字、不會存在的網域
        private static func setDest(_ kind: String) {
            BRIDGE_URL = ""
            CLAUDE_KEY = ""
            AI_ENDPOINT = ""
            switch kind {
            case "bridge":
                BRIDGE_URL = "http://127.0.0.1:9/ask?t=uitest"
            case "key":
                CLAUDE_KEY = "uitest-fake-not-a-key"
            case "endpoint":
                AI_ENDPOINT = "https://ai.example.invalid/ask"
            default:
                break
            }
        }

        private static func write(_ s: AppState) {
            let url: URL = AppStore.defaultURL()
            do {
                let dir: URL = url.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let data: Data = try JSONEncoder().encode(s)
                try data.write(to: url, options: .atomic)
            } catch {
                NSLog("%@", "[uitest-scene] 場景寫不進去：\(error)")
            }
        }

        /* ---------- 場景 ---------- */

        private static func state(_ name: String) -> AppState? {
            switch name {
            case "start": return start()
            case "plan": return plan()
            case "trip": return onTrip()
            case "done": return done()
            case "trips": return manyTrips()
            case "quota": return quota()
            case "route": return route()
            default: return nil
            }
        }

        /// 還沒有這趟，平常的我設過了（開一趟的表單不用答四題）
        private static func start() -> AppState {
            var d: AppState = AppState()
            d.settings = usual()
            return d
        }

        /// 剛排好、十天後出發。還沒看過剛排好那張卡
        private static func plan() -> AppState {
            var d: AppState = start()
            d.trip = makeTrip(10, 5, d.settings)
            return d
        }

        /// 旅途中第 2 天，第 1 天去過了。下一站是有韓文名的吃的站，設了過敏
        private static func onTrip() -> AppState {
            var d: AppState = start()
            let names: [String] = ALLERGENS.prefix(2).map { (a: Allergen) -> String in a.n }
            d.settings.allergy = names
            var trip: Trip = makeTrip(-1, 8, d.settings)
            pull(&trip, [1])
            putFirst(&trip, "p9", 2)
            d.trip = trip
            return d
        }

        /// 回來三天了，去過前三天的站
        private static func done() -> AppState {
            var d: AppState = start()
            var trip: Trip = makeTrip(-8, 5, d.settings)
            pull(&trip, [1, 2, 3])
            d.trip = trip
            return d
        }

        /// 去過的一趟（有花費、有沒去的站）、收起來的一趟、放一邊的一趟、現在這趟（講過一句）
        private static func manyTrips() -> AppState {
            var d: AppState = start()
            var old: Trip = makeTrip(-40, 5, d.settings)
            pull(&old, [1, 2, 3])
            _ = addSpend(&old, 12000, "廣藏市場", 2)
            _ = addSpend(&old, 38000, "烤肉", 3)
            old.rate = 23
            old.flight = 9800
            d.trip = old
            _ = archiveTrip(&d)
            for i in d.baskets.indices {
                d.baskets[i].id = "uitest"
            }
            var closed: Trip = makeTrip(60, 4, d.settings)
            closed.name = "不去了的那趟"
            d.trip = closed
            _ = archiveTrip(&d)
            var other: Trip = makeTrip(30, 6, d.settings)
            other.name = "跟媽媽的首爾"
            d.trip = other
            shelveCurrent(&d)
            d.trip = makeTrip(10, 5, d.settings)
            let ask: String = "有哪些要先訂"
            if let answer = phoneAnswer(ask, d, 1, nil, nil) {
                d.chat.append(ChatMsg(r: .me, t: ask, day: 1))
                d.chat.append(ChatMsg(r: .ai, t: answer, day: 1, local: true, at: Date().timeIntervalSince1970))
            }
            return d
        }

        /// 這趟的 AI 句數用完了（要配 -uitest-dest endpoint，只有走後端的算句數）
        private static func quota() -> AppState {
            var d: AppState = plan()
            if var trip = d.trip {
                trip.aiUsed = AI_FIRST_TRIP_LIMIT
                d.trip = trip
            }
            return d
        }

        /// 第 2 天故意繞路：遠、住的地方旁邊、又跑回遠的。手機算得出改法
        private static func route() -> AppState {
            var d: AppState = start()
            var trip: Trip = makeTrip(10, 5, d.settings)
            for i in trip.slots.indices where trip.slots[i].day == 2 {
                trip.slots[i].items = []
            }
            put(&trip, "p28", 2, .am)
            put(&trip, "p10", 2, .pm)
            put(&trip, "p29", 2, .eve)
            d.trip = trip
            return d
        }

        /* ---------- 組場景用的 ---------- */

        private static func usual() -> Settings {
            var st: Settings = defaultSettings()
            st.play = [.eat: 1, .cafe: 1]
            st.tuned = true
            return st
        }

        /// from 是從今天起幾天後出發，負的是幾天前
        private static func makeTrip(_ from: Int, _ days: Int, _ st: Settings) -> Trip {
            let draft: TripDraft = TripDraft(
                city: "seoul", base: .C, start: addDays(todayISO(), from), days: days, arrive: .am, leave: .pm,
                people: 2)
            var trip: Trip = generate(draft, st)
            trip.planTweaks = []
            return trip
        }

        /// 這幾天的站都當成去過了，每天第一站寫一句
        private static func pull(_ trip: inout Trip, _ days: [Int]) {
            var said: Set<Int> = []
            for i in trip.slots.indices {
                let day: Int = trip.slots[i].day
                if !days.contains(day) { continue }
                for j in trip.slots[i].items.indices {
                    trip.slots[i].items[j].status = .pulled
                    if !said.contains(day) {
                        said.insert(day)
                        trip.slots[i].items[j].say = "排了十分鐘，值得"
                    }
                }
            }
        }

        /// 資料包裡的一站變成行程裡的站。先從這趟別的時段拿掉，免得同一站出現兩次
        private static func takeStop(_ trip: inout Trip, _ id: String) -> Stop? {
            let hit: Place? = PLACES.first { (p: Place) -> Bool in p.id == id }
            guard let place = hit else { return nil }
            for i in trip.slots.indices {
                trip.slots[i].items.removeAll { (it: Stop) -> Bool in it.id == id }
            }
            return planToStop(place, "這一帶順路的小地方")
        }

        /// 放進那一天的那個時段
        private static func put(_ trip: inout Trip, _ id: String, _ day: Int, _ part: Part) {
            guard let si = slotAt(trip, day, part), let it = takeStop(&trip, id) else { return }
            trip.slots[si].items.append(it)
            trip.slots[si].rest = false
        }

        /// 放在那一天的第一站
        private static func putFirst(_ trip: inout Trip, _ id: String, _ day: Int) {
            let found: Int? = trip.slots.firstIndex { (s: Slot) -> Bool in s.day == day && s.off != true }
            guard let si = found, let it = takeStop(&trip, id) else { return }
            trip.slots[si].items.insert(it, at: 0)
            trip.slots[si].rest = false
        }
    }

    /// 攔下要送給 AI 的請求，照 -uitest-ai 回假的。只攔 -uitest-dest 那三個地方，別的網路（地圖）不動
    final class UITestAIProtocol: URLProtocol {
        static var mode: String = "fail"
        private static let hosts: [String] = ["127.0.0.1", "api.anthropic.com", "ai.example.invalid"]

        override class func canInit(with request: URLRequest) -> Bool {
            guard let host = request.url?.host else { return false }
            return hosts.contains(host)
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            return request
        }

        override func startLoading() {
            // slow：一直不回，畫面停在「想一下…」
            if UITestAIProtocol.mode == "slow" { return }
            let ok: Bool = UITestAIProtocol.mode == "ok"
            let status: Int = ok ? 200 : 500
            guard let url = request.url,
                let response = HTTPURLResponse(
                    url: url, statusCode: status, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"])
            else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }
            let body: Data = ok ? UITestAIProtocol.reply(url) : Data("{}".utf8)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}

        /// 第 2 天上午下午對調，晚上多一個 AI 自己提的地方。格式照 Chat.swift 的 brainFromServer、brainFromClaude
        private static func reply(_ url: URL) -> Data {
            if url.path.hasSuffix("/ping") {
                return json(["name": "測試用的電腦"])
            }
            let place: [String: Any] = [
                "n": "首爾路 7017", "kr": "서울로 7017", "c": "nature", "s": "S", "tip": "去之前查一下開放時間",
                "lat": 37.5567, "lng": 126.9707,
            ]
            let swap: [String: Any] = ["op": "swapParts", "day": 2, "a": "am", "b": "pm"]
            let add: [String: Any] = ["op": "add", "day": 2, "part": "eve", "place": place]
            let ops: [[String: Any]] = [swap, add]
            let brain: [String: Any] = [
                "reply": "第 2 天上午和下午對調了，晚上多排一個散步的地方。開放時間去之前查一下。",
                "ops": ops,
            ]
            if url.host == "api.anthropic.com" {
                let text: String = String(data: json(brain), encoding: .utf8) ?? "{}"
                let block: [String: Any] = ["type": "text", "text": text]
                let content: [[String: Any]] = [block]
                return json(["stop_reason": "end_turn", "content": content])
            }
            return json(brain)
        }

        private static func json(_ obj: [String: Any]) -> Data {
            let data: Data? = try? JSONSerialization.data(withJSONObject: obj, options: [])
            return data ?? Data("{}".utf8)
        }
    }
#endif
