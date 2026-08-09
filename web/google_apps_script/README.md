# Google Apps Script deployment

This folder contains the server side of the one-click, end-of-event upload.

## 1. Create the spreadsheet

Create a blank Google spreadsheet. Copy its ID from the URL:

```text
https://docs.google.com/spreadsheets/d/SPREADSHEET_ID/edit
```

The script creates four sheets automatically: `summary`, `scans`,
`operations`, and `uploads`.

## 2. Add the script

In the spreadsheet, open **Extensions > Apps Script**. Replace `Code.gs`
with the contents of [Code.gs](Code.gs).

## 3. Configure Script Properties

Open **Project Settings > Script Properties** and add:

| Property | Value |
| --- | --- |
| `SPREADSHEET_ID` | The spreadsheet ID copied above |
| `UPLOAD_KEY` | A random secret of at least 32 characters |

Use a password manager to generate `UPLOAD_KEY`. Do not put it in the sheet or
inside `Code.gs`.

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

Client transmission remains disabled until the exact deployment URL is known
and the operator explicitly approves sending complete scan and operation logs
to that deployment.

After approval, configure:

- Cloud upload URL: the exact `/exec` URL
- Upload token: the same value as `UPLOAD_KEY`

## Behavior

- Upload is manual and sends the complete local snapshot after the event.
- Stable IDs make retries idempotent.
- Local JSONL and CSV files are never deleted.
- Formula-like values are stored as text.
- A script lock prevents simultaneous stations from interleaving writes.