# ScanPoint

Offline-first checkpoint scanning and event scoring workspace.

## Modules

| Directory | Purpose |
| --- | --- |
| [`scanpoint`](scanpoint/) | Flutter kiosk application used at each scanning station |
| [`web`](web/) | Static GitHub Pages deployment helper and Google Apps Script source |
| [`score_center`](score_center/) | Placeholder for a standalone scorer; the working rules live in `web` |

## Station application

Run Flutter commands from the station module:

```powershell
cd scanpoint
flutter pub get
flutter test
flutter run -d windows
```

## Deployment web

The `web` directory is a zero-build static site. Its GitHub Pages workflow
publishes only that directory.

The site also hosts the scoring page (`score.html`), which turns station
exports or the uploaded spreadsheet into rankings entirely in the browser.

The page can copy `Code.gs`, create an upload key, extract a spreadsheet ID,
and download the latest Windows station package with local `station.json` plus a `cloud.config` containing the spreadsheet ID, Apps Script URL, and upload key.
