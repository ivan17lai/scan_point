Windows x64,免安裝。下載 zip 解壓縮,整個資料夾複製到現場機器即可。

## 賽前設定

在 `scan_point.exe` 旁邊放一份 `station.json`:

```json
{
  "station_id": "CP3",
  "station_name": "水源地",
  "pin": "246810",
  "upload_url": "",
  "upload_token": "",
  "extra_dir": "",
  "export_dir": ""
}
```

**預設 PIN 是 `246810`,部署到現場前請務必改掉。**

站點編號每台機器都要設成不同的值 —— 多台共用一支備份隨身碟時,資料是依站點編號分資料夾的。

## 現場操作

| 動作 | 方式 |
| --- | --- |
| 進入管理台 | `Ctrl+Shift+Alt+X` → 輸入 PIN → Enter |
| 離開程式 | 管理台 →「解除鎖定並關閉程式」 |

完整的鎖定設定、開機自動啟動、當機重啟與讀卡機檢查表,見
[部署文件](https://github.com/ivan17lai/scan_point/blob/main/docs/windows-kiosk.md)。
