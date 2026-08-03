# scan_point — 定向越野掃描站

[![Windows](https://github.com/ivan17lai/scan_point/actions/workflows/windows.yml/badge.svg)](https://github.com/ivan17lai/scan_point/actions/workflows/windows.yml)

無人現場的鍵盤模擬式 NFC 讀卡機記錄程式。選手刷卡 → 畫面與聲音給回饋 → 逐筆寫檔。
桌面版 Flutter,目標平台 Windows,開發期在 macOS 上跑。

## 資料格式

讀卡機以鍵盤模擬方式輸出,一筆資料為:

```
?<卡號>;
```

## 為什麼不怕輸入法

程式裡**沒有任何文字輸入欄位**出現在掃描畫面上。沒有 text input client,IME 就不會啟動,
注音/拼音沒有機會攔截或緩衝讀卡機送出的按鍵。

再往下一層,解碼時讀的是 `KeyEvent.physicalKey`(實體按鍵位置的 USB HID code),自己對照
US-QWERTY 表換成字元 —— 而不是讀系統給的字元。因此同時免疫三件事:

- 輸入法狀態(注音、拼音、倉頡)
- 系統鍵盤配置(注音鍵盤、Dvorak)
- CapsLock

`?` 判斷的是「slash 那顆實體鍵 + Shift」,`;` 判斷的是「semicolon 那顆實體鍵」,都不看字元。

程式碼:[lib/src/scanner/keyboard_layout.dart](lib/src/scanner/keyboard_layout.dart)、
[lib/src/scanner/scan_decoder.dart](lib/src/scanner/scan_decoder.dart)

## 畫面狀態

介面走 Material 3 Expressive,但只取**形狀與動態**,顏色寫死。

| 狀態 | 顏色 | 形狀(邊數 / 圓潤度) | 主要文字 | 停留 |
| --- | --- | --- | --- | --- |
| 待機 | 深藍 `#0E4BA8` | 7 / 0.52,緩慢自轉呼吸 | 請掃描 | — |
| 掃描中 | 琥珀 `#9A5200` | 5→7 變形,快速自轉 | 掃描中 | 最少 0.4 秒 |
| 成功 | 綠 `#16713A` | 7 / 0.62 | 掃描完成 + 巨大卡號 | 2.5 秒 |
| 已記錄過 | 藍紫 `#4B3BAE` | 6 / 0.40,六個明顯凸角 | 已記錄過 + 首刷時間 | 3.0 秒 |
| 失敗 | 紅 `#A81E1E` | 4 / 0.30(明顯尖銳) | 請再刷一次 + 錯誤碼 | 3.5 秒 |

**為什麼不用 `DynamicSchemeVariant.expressive` 產生配色。** 試過,而且被否決了:那個變體為了品牌
表現會大幅旋轉色相 —— 藍色種子產出深綠、綠色種子產出紅褐、紅色種子產出藍。在一個「顏色就是訊息」
的畫面上(綠代表記錄成功、紅代表請重刷),一個會重新指派色相的演算法是危險,不是特色。狀態配色
因此固定寫在 [kiosk_face.dart](lib/src/ui/kiosk_face.dart) 裡,誰都不能改。M3E 真正被採用的是另外
兩半:形狀([expressive_shape.dart](lib/src/ui/m3e/expressive_shape.dart))與彈簧動態
([expressive_motion.dart](lib/src/ui/m3e/expressive_motion.dart))。

形狀是用極座標半徑函數生成的圓角多邊形,可以在小數邊數之間連續變形。小數邊數不能直接餵進多邊形
公式(`2π/n` 除不盡,輪廓收不回起點會留下接縫凹口),所以實作是在相鄰的兩個**整數**多邊形之間內插。

幾個刻意的決定:

- **掃描中有 0.4 秒下限。** 讀卡機一筆資料只要 20–80ms,照實顯示會閃一下像壞掉。
- **待機畫面會呼吸。** 靜止畫面跟當機無法分辨,選手會以為機器死了而跳過站點。
- **重複刷卡是藍紫不是紅。** 選手不確定有沒有刷到而再刷一次很常見,那不是錯誤。
- **聲音是主要回饋。** 成功兩聲高音、重複一聲中音、失敗長聲低音,選手通常刷完就跑不看螢幕。
- **形狀也帶語意。** 失敗是四邊形、尖角明顯,跟其他狀態的圓潤多邊形在輪廓上就分得出來,
  對色覺辨識有困難的人多一層線索。

### 看畫面長什麼樣

不需要讀卡機或現場機器:

```bash
KIOSK_RENDER_DIR=/tmp/kiosk-shots flutter test test/kiosk_face_render_test.dart
```

五個狀態會各輸出一張 PNG。這是把畫面拆成純呈現層 `KioskFace`(只吃資料、不吃 controller)
換來的 —— 見 [kiosk_face.dart](lib/src/ui/kiosk_face.dart) 與
[kiosk_screen.dart](lib/src/ui/kiosk_screen.dart)。

## 錯誤碼

| 碼 | 意思 |
| --- | --- |
| `E-01` | 兩個字元間隔太久 —— 卡片中途移開,或有人在手打 |
| `E-02` | 收到 `?` 但等不到結尾 |
| `E-03` | 卡號是空的、太長,或含有不該出現的字元 |
| `E-10` | 寫入紀錄失敗 |

## 儲存

沒有資料庫。每一筆同時寫三個地方,逐筆 flush:

| 位置 | 用途 |
| --- | --- |
| `<程式資料夾>/data/scans.jsonl` | 主紀錄 |
| `<文件>/OrienteeringSystem/mirror/scans.jsonl` | 另一個位置的鏡像 |
| `<程式資料夾>/data/scans-YYYY-MM-DD.csv` | 試算表格式 |

用 append-only 純文字而不是資料庫,是因為無人站點最實際的故障是斷電。文字檔最壞的情況是
「最後一行寫到一半」,前面全部完好;資料庫寫到一半的頁面可能整份帶走。啟動時如果主檔比鏡像
短,會自動改用鏡像。

### 額外備份到隨身碟

管理台的「儲存位置」可以指定一個**額外備份資料夾**,例如隨身碟。那是預設三份之外**多寫的第四
份** —— 預設的位置照常寫,不會被取代。隨身碟拔掉時,原本的備援完全不受影響。

這份額外備份同時寫 `scans.jsonl` 和當日 CSV,所以隨身碟拔下來就能直接用試算表打開,不需要
先做匯出。

**預設兩份的位置不開放更改。** 它們必須永遠掛載、永遠可寫;若指向隨身碟而中途鬆脫,山上這台
機器會靜默地停止記錄,而現場沒有人會發現。只要有一份 JSONL 寫成功就算記錄成功,其餘失敗只會
在畫面底部顯示警告。

選擇資料夾時會先**實際寫一個測試檔**再接受,因為「資料夾存在」不等於「寫得進去」:隨身碟可能
是唯讀的,網路磁碟可能掛載了但沒有寫入權限。設定後既有紀錄會**整份複製**過去,不是只從那一刻
開始記。設定的額外資料夾若在啟動時不可用(隨身碟忘了插),程式照常啟動與記錄,只是帶著警告。

匯出目的地則是單純的重導向 —— 它是一次性的操作,沒有備援角色。

> **macOS 限制:** app 有沙盒,透過選擇器授予的資料夾權限只在本次執行有效,**重開程式後會失效**。
> Windows 沒有沙盒,不受影響。要在 macOS 上長期使用自訂路徑,得移除
> `macos/Runner/*.entitlements` 裡的 `com.apple.security.app-sandbox`。

重複刷卡也會寫進紀錄(`duplicate_of` 欄位標記首刷時間),但不計入「已記錄 N 筆」。

## 操作

| 動作 | 方式 |
| --- | --- |
| 進入管理台 | `Ctrl+Shift+Alt+X` → 輸入 PIN → Enter |
| 取消 PIN 輸入 | `Esc` |
| 離開程式 | 管理台 →「解除鎖定並關閉程式」 |

PIN 讀的也是實體數字鍵,同樣不受輸入法影響;畫面上另外有數字鍵盤,翻轉筆電折起來時可用。

預設 PIN 是 `246810`,**現場部署前請改掉**。

## 站點設定

`station.json`,讀取優先序:

1. 執行檔旁邊 —— 賽前預先設定好交給工作人員的那份
2. `<文件>/OrienteeringSystem/station.json`
3. 程式資料夾 —— 管理台寫入的那份

```json
{
  "station_id": "CP3",
  "station_name": "水源地",
  "pin": "246810",
  "upload_url": "",
  "upload_token": ""
}
```

管理台改設定會寫進 2 和 3。**放在執行檔旁邊的那份優先權最高**,現場改完設定若要生效,
記得把它刪掉。

## 上傳

管理台的「上傳到雲端」會把全部紀錄 POST 到 `upload_url`:

```json
{
  "station_id": "CP3",
  "station_name": "水源地",
  "uploaded_at": "2026-08-03T10:24:32.000",
  "records": [ { "seq": 1, "card": "A7F3C210", "at_local": "…" } ]
}
```

有填 `upload_token` 就會帶 `Authorization: Bearer <token>`。上傳不刪本機紀錄,可重複執行。
沒設定網址時,管理台只提供「匯出全部紀錄」。

## 鎖定畫面

跨平台的部分(全螢幕、永遠置頂、擋關閉視窗、禁止休眠)在
[lib/src/platform/kiosk_lock.dart](lib/src/platform/kiosk_lock.dart)。真正擋住切換程式的
部分必須是原生的:

- Windows:[windows/runner/kiosk_lock.cpp](windows/runner/kiosk_lock.cpp) —— 低階鍵盤掛鉤
  吃掉 Alt+Tab、Win、Alt+F4、Ctrl+Esc。**Ctrl+Alt+Del 攔不掉**,見部署文件。
- macOS:[macos/Runner/KioskLock.swift](macos/Runner/KioskLock.swift) ——
  `NSApplicationPresentationOptions` 擋掉 Cmd+Tab、Dock、選單列;Cmd+Q 由 AppDelegate 拒絕。

## 開發

```bash
flutter run -d macos
```

```bash
flutter test
```

現場建置與 Windows 鎖定設定見 [docs/windows-kiosk.md](docs/windows-kiosk.md)。
