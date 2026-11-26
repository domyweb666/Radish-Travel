# 送 TestFlight：你要親手做的三件事

工作流是 `.github/workflows/ios.yml`，照人蔘修煉那條抄的。程式這邊都接好了，剩下三件事只有你能做，因為要登入 Apple 和動到金鑰。做完大概二十分鐘。

我（AI）不會替你登入 Apple，也不會碰你的密碼和金鑰。卡住就截圖那一頁給我看。

## 一、在 Apple 後台登記 App ID

1. 開 https://developer.apple.com/account/resources/identifiers/list
2. 按「+」，選「App IDs」，Continue；選「App」，Continue。
3. Description 填 `Radish Travel`。
4. Bundle ID 選「Explicit」，填 `org.domyweb.radish`。
5. Capabilities 都不用勾。這一版沒有用到推播、iCloud、App Groups。
6. Continue，Register。

## 二、在 App Store Connect 建 app 記錄

1. 開 https://appstoreconnect.apple.com/apps
2. 按「+」，New App。
3. Platforms 勾 iOS。
4. Name 填 `蘿蔔旅行`。這個名字在整個 App Store 要獨一無二，被用了就先填 `蘿蔔旅行：首爾行程`，上架前可以再改。
5. Primary Language 選「Chinese (Traditional)」。
6. Bundle ID 選 `org.domyweb.radish`。
7. SKU 填 `radish-ios`。
8. User Access 選 Full Access。Create。

## 三、把六個 secrets 放進這個 repo

發佈憑證是整個開發者帳號共用的，API 金鑰也是。所以這六個值跟人蔘修煉那個 repo 放的一模一樣，不用重做憑證。GitHub 不讓人把 secret 讀出來，所以要從你電腦上原本那幾個檔再放一次。

開 https://github.com/domyweb666/Radish-Travel/settings/secrets/actions ，按「New repository secret」，一個一個加：

| 名字 | 放什麼 |
|---|---|
| `APPLE_DIST_P12_BASE64` | 發佈憑證 .p12 轉成 base64 的那一串 |
| `APPLE_DIST_P12_PASSWORD` | 那個 .p12 的密碼 |
| `APPLE_TEAM_ID` | 十碼的 Team ID，在 https://developer.apple.com/account 的 Membership details |
| `ASC_KEY_P8_BASE64` | App Store Connect API 金鑰 .p8。貼檔案原文或 base64 都可以 |
| `ASC_KEY_ID` | 那把金鑰的 Key ID（十碼） |
| `ASC_ISSUER_ID` | Issuer ID（一長串有連字號的） |

不想開網頁一個一個貼的話，可以在 Git Bash 用 `gh` 放。檔案路徑換成你電腦上的：

```bash
base64 -w0 "你的憑證.p12" | gh secret set APPLE_DIST_P12_BASE64 --repo domyweb666/Radish-Travel
```

```bash
gh secret set ASC_KEY_P8_BASE64 --repo domyweb666/Radish-Travel < "AuthKey_你的KeyID.p8"
```

```bash
gh secret set APPLE_DIST_P12_PASSWORD --repo domyweb666/Radish-Travel
```

最後那一行不帶值，它會停下來等你打，打的字不會顯示也不會留在指令紀錄裡。`APPLE_TEAM_ID`、`ASC_KEY_ID`、`ASC_ISSUER_ID` 同樣的寫法。

API 金鑰要 App Manager 等級以上。人蔘修煉用的那一把就可以。

## 做完之後怎麼出一版

推一個 `tf-` 開頭的標籤：

```bash
git tag tf-8 && git push origin tf-8
```

標籤不能重複，2026-11-25 已經用到 `tf-7`，下一版就 `tf-8`、`tf-9`。用到哪一號可以跑 `git tag -l "tf-*"` 看。平常推程式不會出 TestFlight 版本，只跑檢查線。

十五到二十分鐘後，手機上的 TestFlight 會出現「蘿蔔旅行」。版本號照 `ios/project.yml` 的 `MARKETING_VERSION`，現在是 `0.5.0`，要換版號就改那一行；後面括號裡的數字是這條工作流跑的第幾次。

第一次送，Apple 可能會寄信問出口合規或缺什麼說明，把信轉給我看。

## 會紅在哪、怎麼看

| 紅在哪一步 | 多半是什麼 |
|---|---|
| 六個 secrets 都放了嗎 | 訊息會直接列出少哪幾個 |
| 還原發佈憑證到暫時鑰匙圈 | .p12 或密碼不對 |
| 還原 App Store Connect API 金鑰 | .p8 貼壞了，訊息會寫大小和開頭對不對 |
| 向 Apple 申請上架用描述檔 | 第一件事（App ID）還沒做，或 Bundle ID 打錯 |
| archive | 簽章對不上，把紀錄給我看 |
| 上傳 App Store Connect | 第二件事（app 記錄）還沒做；偶爾是 Apple 那邊暫時失敗，重跑就好 |

macOS 機器排不到的時候那一關會顯示 cancelled、步驟數 0，那不是壞掉，重跑就好。

## 腳本

| 檔 | 做什麼 |
|---|---|
| `restore_asc_key.sh` | 把 API 金鑰從 secret 還原成檔案，先驗格式 |
| `appstore_profile.mjs` | 向 Apple 申請一張叫「Radish CI App Store」的上架用描述檔，每次重建 |
| `asc_api.mjs` | App Store Connect API 的簽章與呼叫 |
| `testflight_notes.mjs` | 等 Apple 處理完建置，填測試說明 |
| `ExportOptions.plist` | 匯出與上傳的設定 |

測試說明的文字寫在 `.github/workflows/ios.yml` 的 `TESTFLIGHT_NOTES`，每出一版記得改。
