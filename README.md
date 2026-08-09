# ScanPoint

Offline-first checkpoint scanning and event scoring workspace.

## Modules

| Directory | Purpose |
| --- | --- |
| [`scanpoint`](scanpoint/) | Flutter kiosk application used at each scanning station |
| [`web`](web/) | Static GitHub Pages deployment helper and Google Apps Script source |
| [`score_center`](score_center/) | Reserved module for result calculation and ranking |

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

The page can copy `Code.gs`, create an upload key, extract a spreadsheet ID,
and download a `station.json` compatible with the Flutter station app.
