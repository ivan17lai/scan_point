# Google Apps Script deployment

This folder contains the server side of the one-click, end-of-event upload and
the read-only Score Center endpoint.

## 1. Create the spreadsheet

Create and open a blank Google spreadsheet. Its URL looks like:

```text
https://docs.google.com/spreadsheets/d/SPREADSHEET_ID/edit
```

The value between `/d/` and `/edit` is the spreadsheet ID.

## 2. Generate the configured Code.gs

Open the ScanPoint deployment page and paste the complete spreadsheet URL. The
page extracts `SPREADSHEET_ID` and generates two random secrets:

- `UPLOAD_KEY`: used by ScanPoint stations to upload records;
- `READ_KEY`: used by Score Center to read scan rows.

The two keys can be identical, but separate values are recommended so a leaked
read-only key cannot be used to forge uploads.

Choose one configuration mode on the deployment page:

- **Automatic:** the page writes all three values directly into the
  `SCANPOINT_CONFIG` block of the prepared `Code.gs`.
- **Script Properties:** the prepared `Code.gs` keeps its placeholders and
  reads `SPREADSHEET_ID`, `UPLOAD_KEY`, and `READ_KEY` from Apps Script
  **Project Settings > Script Properties**. The deployment page lists each
  exact name and value for copying.

Values are processed only inside the browser and are not uploaded to the
ScanPoint website. Download `scanpoint-keys.json` and store it securely; it
contains both upload and read credentials.

## 3. Add the prepared script

In the spreadsheet, open **Extensions > Apps Script**:

1. Select `Code.gs`.
2. Delete all default code.
3. Use the deployment page to copy or download the prepared `Code.gs`.
4. Paste the complete file and save it.

When using automatic mode, the placeholders must be replaced by the generated
values. When using Script Properties mode, the placeholders intentionally
remain and the script falls back to the three properties created in Project
Settings.

## 4. Deploy the web app

Choose **Deploy > New deployment > Web app**:

- Execute as: **Me**
- Who has access: **Anyone**

Authorize and deploy, then copy the URL ending in `/exec`:

```text
https://script.google.com/macros/s/DEPLOYMENT_ID/exec
```

Do not use the `/dev` test URL.

## 5. Connect the Flutter station

Place `cloud.config` next to `scan_point.exe`. It must contain:

- `SPREADSHEET_ID`: the same spreadsheet ID configured in Apps Script
- `UPLOAD_URL`: the exact `/exec` URL
- `UPLOAD_KEY`: the same upload key configured in Apps Script

The server rejects a station whose `SPREADSHEET_ID` does not match its Apps
Script configuration. Client transmission remains disabled until the operator
explicitly starts the end-of-event upload.

## 6. Open Score Center

Open `score.html`, enter the same `/exec` URL and either type `READ_KEY` or
upload `scanpoint-keys.json`, then load the scan rows. The key is used only in
the current browser page and is not embedded in the public site. Score Center
can also import exported CSV, JSON, and JSONL files without a network
connection.

## Behavior

- Upload is manual and sends the complete local snapshot after the event.
- Stable IDs make retries idempotent.
- Local JSONL and CSV files are never deleted.
- Formula-like values are stored as text.
- A script lock prevents simultaneous stations from interleaving writes.