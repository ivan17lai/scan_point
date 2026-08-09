# ScanPoint deployment web

Zero-dependency static deployment helper for GitHub Pages.

It provides:

- one-click copy and download of `google_apps_script/Code.gs`;
- local, cryptographically secure `UPLOAD_KEY` generation;
- extraction of `SPREADSHEET_ID` from a Google Sheets URL;
- download of a ScanPoint-compatible `station.json`.

No form value is sent to a server or stored by the page. GitHub Pages serves
only the files in this directory through `.github/workflows/pages.yml`.

## Local preview

The page fetches `Code.gs`, so serve this folder over HTTP rather than opening
`index.html` directly. For example:

```powershell
python -m http.server 8080 --directory web
```

Then open `http://localhost:8080`.

## GitHub Pages

1. Push the repository to GitHub.
2. Open **Settings > Pages**.
3. Set **Source** to **GitHub Actions**.
4. Push to `main` or run the `GitHub Pages` workflow manually.
