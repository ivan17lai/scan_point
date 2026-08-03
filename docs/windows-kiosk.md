# Windows 現場部署

App 自己能做到的鎖定都寫在程式裡了(全螢幕、永遠置頂、擋 Alt+Tab / Win / Alt+F4 / Ctrl+Esc、
禁止關閉視窗、禁止休眠)。這份文件是**剩下那些 app 攔不到、必須改機器設定**的部分。

全部指令都要用**系統管理員**身分執行,並在賽前先在同一台機器上演練一次。

---

## 1. 取得執行檔

**不用自己編。** 兩個管道:

**Releases(推薦,不需要 GitHub 帳號)**

[Releases 頁面](https://github.com/ivan17lai/scan_point/releases)下載 zip,任何人拿到連結
都能下載。要發一版:

```bash
git tag v1.0.0 && git push origin v1.0.0
```

推 tag 之後 CI 會自動建置並把 zip 掛上去。

**Actions artifact(每次 push 都有,但需要登入)**

到 [Actions 頁面](https://github.com/ivan17lai/scan_point/actions)挑一個綠色的 run,在
**run 摘要頁最下方**的 Artifacts 區塊下載 `scan_point-windows-x64`。注意 artifact 即使在
公開 repo 也**必須登入 GitHub 才能下載**,匿名訪客看得到名稱但沒有下載按鈕 —— 要給沒有帳號的
工作人員,用 Releases。

兩者內容相同:解壓縮就是完整的程式資料夾,**不需要安裝程式**,整個資料夾複製到現場機器即可。

zip 內含 Visual C++ 執行階段(`msvcp140.dll`、`vcruntime140.dll`、`vcruntime140_1.dll`)。
Flutter 預設不會打包這些,而乾淨的 Windows 沒有它們 —— 少了就會在啟動時跳「找不到
MSVCP140.dll」。現場機器**不需要另外安裝 VC++ Redistributable**。

要自己編的話,在 Windows 機器上(不是 mac):

```bash
flutter build windows --release
```

產物在 `build\windows\x64\runner\Release\`。

## 2. 賽前預先設定站點

在 `scan_point.exe` **旁邊**放一個 `station.json`:

```json
{
  "station_id": "CP3",
  "station_name": "水源地",
  "pin": "246810",
  "upload_url": "",
  "upload_token": ""
}
```

放在 exe 旁邊的設定檔優先權最高,現場如果要改,先在管理台改(會寫到
`文件\OrienteeringSystem\station.json` 和程式資料夾),**並把 exe 旁邊那份刪掉**,否則下次
啟動還是會讀回原本的。

## 3. Ctrl+Alt+Del(程式攔不掉,要靠原則)

Ctrl+Alt+Del 是 Windows 的安全注意序列(SAS),任何使用者模式的程式都攔不到。要擋住它後面
那張畫面上的選項,用群組原則:

```bash
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v DisableTaskMgr /t REG_DWORD /d 1 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v DisableLockWorkstation /t REG_DWORD /d 1 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v DisableChangePassword /t REG_DWORD /d 1 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v NoLogoff /t REG_DWORD /d 1 /f
```

賽後還原:把上面每一行的 `/d 1` 改成 `/d 0`,或直接 `reg delete ... /f`。

## 4. 開機自動啟動

```bash
schtasks /create /tn "OrienteeringStation" /tr "C:\orienteering\scan_point.exe" /sc onlogon /rl highest /f
```

搭配自動登入(讓機器重開後不需要有人輸入密碼):

```bash
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v AutoAdminLogon /t REG_SZ /d 1 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultUserName /t REG_SZ /d "station" /f
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultPassword /t REG_SZ /d "你的密碼" /f
```

> 自動登入會把密碼以明文寫進登錄檔。只在專用的比賽機器上這樣做,賽後把這三個值刪掉。

## 5. 關掉會蓋住畫面的東西

```bash
:: 通知與焦點小幫手
reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\PushNotifications" /v ToastEnabled /t REG_DWORD /d 0 /f
:: Windows Update 自動重開機
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v NoAutoRebootWithLoggedOnUsers /t REG_DWORD /d 1 /f
:: 電源:永不關螢幕、永不睡眠(接電源與電池都設)
powercfg /change monitor-timeout-ac 0
powercfg /change monitor-timeout-dc 0
powercfg /change standby-timeout-ac 0
powercfg /change standby-timeout-dc 0
:: 闔上螢幕不要睡(翻轉筆電折起來時很重要)
powercfg /setacvalueindex SCHEME_CURRENT 4f971e89-eebd-4455-a8de-9e59040e7347 5ca83367-6e45-459f-a27b-476b1d01c936 0
powercfg /setdcvalueindex SCHEME_CURRENT 4f971e89-eebd-4455-a8de-9e59040e7347 5ca83367-6e45-459f-a27b-476b1d01c936 0
powercfg /setactive SCHEME_CURRENT
```

## 6. 當機自動重啟

排程工作加上重啟條件:

```bash
schtasks /create /tn "OrienteeringWatchdog" /tr "cmd /c tasklist | find /i \"scan_point.exe\" || start \"\" \"C:\orienteering\scan_point.exe\"" /sc minute /mo 1 /rl highest /f
```

每分鐘檢查一次,程式不在就重開。紀錄是逐筆寫檔的,重啟不會掉資料,重啟後計數會從檔案讀回來。

## 7. 掃描器設定檢查表

現場插上讀卡機後,**在記事本裡刷一張卡**,確認輸出長這樣:

```
?A7F3C210;
```

- 若少了 `?` 或 `;` → 到讀卡機的設定工具補上 prefix / suffix。
- 若尾巴多了換行 → 沒關係,程式會把 Enter 當成結尾接受,並在紀錄裡標成 `enterKey`。
  賽後看到大量 `enterKey` 就表示 `;` 沒設好,值得回頭修。
- 若刷出來是中文或亂碼 → **不用管**,那是記事本經過輸入法的結果,本程式讀的是實體按鍵,
  不受輸入法影響。要驗證請直接在本程式上刷。

## 8. 賽後取資料

管理台(`Ctrl+Shift+Alt+X` → PIN)→「匯出全部紀錄」,檔案會出現在:

```
文件\OrienteeringSystem\export\export-<時間>\
```

三份互相對帳的檔案:

| 檔案 | 內容 |
| --- | --- |
| `scans.jsonl` | 主紀錄,一行一筆,逐筆 flush |
| `scans-YYYY-MM-DD.csv` | 同樣內容的試算表格式 |
| `文件\OrienteeringSystem\mirror\scans.jsonl` | 另一個磁碟位置的鏡像 |

`duplicate_of` 有值的那幾行是重複刷卡,計數時要排除。

## 9. 已知限制

- **Ctrl+Alt+Del 擋不掉。** 見第 3 節,只能靠原則把後面的選項關掉。
- **鍵盤掛鉤需要程式活著。** 程式當掉時掛鉤會隨行程消失,鍵盤恢復正常 —— 這是刻意的,
  不會把整台機器鎖死。
- **實體電源鍵擋不掉。** 現場請把機器放在選手構不到電源鍵的位置。
