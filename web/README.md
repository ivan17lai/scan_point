# ScanPoint project and deployment web

Zero-dependency project overview and deployment helper for GitHub Pages.

It introduces the offline station workflow and three-module architecture, then provides:

- local, cryptographically secure `UPLOAD_KEY` and `READ_KEY` generation;
- extraction of `SPREADSHEET_ID` from a Google Sheets URL;
- two deployment modes: embed values in `Code.gs` or configure Apps Script properties;
- one-click copy and download of the mode-specific `Code.gs`;
- download of a local `UPLOAD_KEY` / `READ_KEY` backup file;
- browser-side assembly of the latest Windows package with local `station.json` and remote-upload `cloud.config`;
- browser-only score calculation from Apps Script, CSV, JSON, or JSONL;
- local key-backup import to fill the Score Center `READ_KEY`.

Station values and `cloud.config` credentials are added to the ZIP locally in the browser; they are not sent to GitHub or stored by the page. GitHub Pages serves
the static files plus the latest successful Windows build through `.github/workflows/pages.yml`.

## Local preview

The deployment page fetches `Code.gs`, so serve this folder over HTTP rather
than opening
`index.html` directly. For example:

```powershell
python -m http.server 8080 --directory web
```

Then open `http://localhost:8080`.

## GitHub Pages

1. Push the repository to GitHub.
2. Open **Settings > Pages**.
3. Set **Source** to **GitHub Actions**.
4. Push to `main`; after the Windows workflow succeeds, the Pages workflow deploys the matching Windows ZIP automatically.
