// 同意把資料送給 AI：照送去的地方記。同一地方不重問，換地方要再問，舊檔的旗標不算數。
// SwiftUI 版才有，mobile/tests 沒有對應的。
import XCTest

@testable import RadishCore

final class ConsentTests: XCTestCase {
    private var oldKey: String = ""
    private var oldEnd: String = ""
    private var oldBridge: String = ""

    override func setUp() {
        super.setUp()
        oldKey = CLAUDE_KEY
        oldEnd = AI_ENDPOINT
        oldBridge = BRIDGE_URL
        CLAUDE_KEY = ""
        AI_ENDPOINT = ""
        BRIDGE_URL = ""
    }

    override func tearDown() {
        CLAUDE_KEY = oldKey
        AI_ENDPOINT = oldEnd
        BRIDGE_URL = oldBridge
        super.tearDown()
    }

    /// 現在會送去哪裡，跟著同意那裡
    private func agreeNow(_ d: inout AppState) throws {
        let dest: AIDest = try XCTUnwrap(aiDestNow())
        agreeAI(&d, dest)
    }

    private func json(_ text: String) -> Data {
        return Data(text.utf8)
    }

    func test送去哪裡_順序是電腦CLI_金鑰_後端() throws {
        XCTAssertNil(aiDestNow())
        XCTAssertFalse(aiReady())
        AI_ENDPOINT = "https://api.example.com/v1/ask"
        XCTAssertEqual(aiDestNow(), AIDest(kind: .server, origin: "https://api.example.com"))
        XCTAssertTrue(aiMetered())
        CLAUDE_KEY = "sk-ant-test"
        XCTAssertEqual(aiDestNow(), AIDest(kind: .key, origin: "https://api.anthropic.com"))
        XCTAssertFalse(aiMetered())
        BRIDGE_URL = "http://192.168.1.23:8787/ask?t=0123abcd"
        XCTAssertEqual(aiDestNow(), AIDest(kind: .bridge, origin: "http://192.168.1.23:8787"))
        XCTAssertFalse(aiMetered())
    }

    func test位址只留主機和埠_大小寫算同一個_讀不出來是空的() {
        XCTAssertEqual(aiOrigin("http://My-Mac.local:8787/ask?t=abc"), "http://my-mac.local:8787")
        XCTAssertEqual(aiOrigin("https://user:pass@example.com/ai"), "https://example.com")
        XCTAssertEqual(aiOrigin(""), "")
        XCTAssertEqual(aiOrigin("example"), "")
    }

    func test同一個地方不重問_轉接程式重開換密碼也不重問() throws {
        var d: AppState = AppState()
        BRIDGE_URL = "http://192.168.1.23:8787/ask?t=aaaa"
        XCTAssertFalse(aiAllowed(d, aiDestNow()))
        try agreeNow(&d)
        XCTAssertTrue(aiAllowed(d, aiDestNow()))
        BRIDGE_URL = "http://192.168.1.23:8787/ask?t=bbbb"
        XCTAssertTrue(aiAllowed(d, aiDestNow()))
        try agreeNow(&d)
        XCTAssertEqual(d.aiAgreed.count, 1, "同一個地方只記一次")
    }

    func test換地方要再問_換回同意過的地方不重問() throws {
        var d: AppState = AppState()
        AI_ENDPOINT = "https://api.example.com/ask"
        try agreeNow(&d)
        CLAUDE_KEY = "sk-ant-test"
        XCTAssertFalse(aiAllowed(d, aiDestNow()), "後端換成自己的金鑰")
        try agreeNow(&d)
        BRIDGE_URL = "http://192.168.1.23:8787/ask?t=aaaa"
        XCTAssertFalse(aiAllowed(d, aiDestNow()), "金鑰換成電腦")
        try agreeNow(&d)
        BRIDGE_URL = "http://192.168.1.99:8787/ask?t=aaaa"
        XCTAssertFalse(aiAllowed(d, aiDestNow()), "換了一台電腦")
        BRIDGE_URL = ""
        XCTAssertTrue(aiAllowed(d, aiDestNow()), "換回金鑰")
        CLAUDE_KEY = ""
        XCTAssertTrue(aiAllowed(d, aiDestNow()), "換回後端")
        AI_ENDPOINT = "https://other.example.com/ask"
        XCTAssertFalse(aiAllowed(d, aiDestNow()), "後端換了網址")
        AI_ENDPOINT = ""
        XCTAssertFalse(aiAllowed(d, aiDestNow()), "沒接 AI")
    }

    func test位址讀不出來的不算同意過() {
        var d: AppState = AppState()
        let odd: AIDest = AIDest(kind: .server, origin: "")
        agreeAI(&d, odd)
        XCTAssertTrue(d.aiAgreed.isEmpty)
        XCTAssertFalse(aiAllowed(d, odd))
    }

    func test等同意時地方換了_不送_重新問() {
        let a: AIDest = AIDest(kind: .server, origin: "https://api.example.com")
        let b: AIDest = AIDest(kind: .key, origin: "https://api.anthropic.com")
        XCTAssertEqual(consentStep(a, a), ConsentStep.send(a))
        XCTAssertEqual(consentStep(a, b), ConsentStep.askAgain(b))
        XCTAssertEqual(consentStep(a, nil), ConsentStep.gone)
    }

    func test送的那一刻地方跟同意的不一樣_不送() async {
        CLAUDE_KEY = "sk-ant-test"
        let agreed: AIDest = AIDest(kind: .server, origin: "https://api.example.com")
        do {
            _ = try await askAI("測試", agreed)
            XCTFail("不應該送出去")
        } catch let e as AskError {
            XCTAssertEqual(e, AskError.destChanged)
        } catch {
            XCTFail("不應該是別的錯：\(error)")
        }
    }

    func test舊檔_只有aiConsent的當成沒同意_其他照樣讀得出來() throws {
        let old: Data = json("{\"aiConsent\":true,\"guideSeen\":true,\"pool\":[\"x1\"]}")
        let d: AppState = try XCTUnwrap(AppState.hydrate(old))
        XCTAssertTrue(d.aiAgreed.isEmpty)
        XCTAssertTrue(d.guideSeen)
        XCTAssertEqual(d.pool, ["x1"])
        AI_ENDPOINT = "https://api.example.com/ask"
        XCTAssertFalse(aiAllowed(d, aiDestNow()), "要再問一次")
    }

    func test存檔_同意過的地方讀得回來_不含密碼和金鑰() throws {
        var d: AppState = AppState()
        BRIDGE_URL = "http://192.168.1.23:8787/ask?t=SECRETTOKEN"
        try agreeNow(&d)
        BRIDGE_URL = ""
        CLAUDE_KEY = "sk-ant-SECRETKEY"
        try agreeNow(&d)
        let data: Data = try JSONEncoder().encode(d)
        let text: String = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(text.contains("SECRET"))
        XCTAssertFalse(text.contains("aiConsent"))
        let back: AppState = try XCTUnwrap(AppState.hydrate(data))
        XCTAssertEqual(back.aiAgreed, d.aiAgreed)
        XCTAssertEqual(back.aiAgreed.count, 2)
    }

    func test同意那一欄讀不懂_當成沒同意_不會整包讀不回來() throws {
        let odd: Data = json("{\"aiAgreed\":[{\"kind\":\"moon\",\"origin\":\"x\"}],\"guideSeen\":true}")
        let d: AppState = try XCTUnwrap(AppState.hydrate(odd))
        XCTAssertTrue(d.aiAgreed.isEmpty)
        XCTAssertTrue(d.guideSeen)
    }

    func test貼上備份_留這支手機自己的同意_收回是全部收回() {
        let mine: AIDest = AIDest(kind: .key, origin: "https://api.anthropic.com")
        let theirs: AIDest = AIDest(kind: .bridge, origin: "http://10.0.0.5:8787")
        var phone: AppState = AppState()
        agreeAI(&phone, mine)
        var backup: AppState = AppState()
        agreeAI(&backup, theirs)
        keepAgreed(&backup, phone)
        XCTAssertEqual(backup.aiAgreed, [mine])

        var fresh: AppState = AppState()
        agreeAI(&fresh, theirs)
        keepAgreed(&fresh, AppState())
        XCTAssertTrue(fresh.aiAgreed.isEmpty, "這支手機沒同意過，備份帶不進來")

        agreeAI(&phone, theirs)
        XCTAssertEqual(phone.aiAgreed.count, 2)
        revokeAI(&phone)
        XCTAssertTrue(phone.aiAgreed.isEmpty)
    }

    func test說明的字_三個地方各寫各的() {
        let bridge: String = aiWhereText(AIDest(kind: .bridge, origin: "http://192.168.1.23:8787"))
        XCTAssertTrue(bridge.contains("192.168.1.23:8787"))
        XCTAssertTrue(bridge.contains("沒有加密"))
        let safe: String = aiWhereText(AIDest(kind: .bridge, origin: "https://my-mac.example.com"))
        XCTAssertFalse(safe.contains("沒有加密"))
        let key: String = aiWhereText(AIDest(kind: .key, origin: "https://api.anthropic.com"))
        XCTAssertTrue(key.contains("費用算在你的 Anthropic 帳號"))
        let server: String = aiWhereText(AIDest(kind: .server, origin: "https://api.example.com"))
        XCTAssertTrue(server.contains("蘿蔔旅行的伺服器（api.example.com）"))
    }
}
