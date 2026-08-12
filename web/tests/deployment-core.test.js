"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const core = require("../deployment-core.js");
const JSZip = require("../vendor/jszip.min.js");

const spreadsheetId = "1AbCdEfGhIjKlMnOpQrStUvWxYz123456789";
const uploadUrl = "https://script.google.com/macros/s/deployment-id/exec";
const uploadKey = "UPLOAD_KEY_1234567890";
const readKey = "READ_KEY_123456789012";

test("parseSpreadsheetId accepts a Google Sheets URL and a raw ID", () => {
  assert.equal(
    core.parseSpreadsheetId(
      `https://docs.google.com/spreadsheets/d/${spreadsheetId}/edit#gid=0`,
    ),
    spreadsheetId,
  );
  assert.equal(core.parseSpreadsheetId(spreadsheetId), spreadsheetId);
  assert.equal(core.parseSpreadsheetId("not a spreadsheet"), "");
});

test("normalizeCloudConfig rejects incomplete values and trims valid input", () => {
  assert.throws(
    () => core.normalizeCloudConfig({}),
    (error) => error.message === "SPREADSHEET_ID_INVALID",
  );
  assert.throws(
    () =>
      core.normalizeCloudConfig({
        spreadsheetSource: spreadsheetId,
        uploadUrl: "https://example.com/exec",
        uploadKey,
        readKey,
      }),
    (error) => error.message === "UPLOAD_URL_INVALID",
  );
  assert.throws(
    () =>
      core.normalizeCloudConfig({
        spreadsheetSource: spreadsheetId,
        uploadUrl,
        uploadKey: "has whitespace",
        readKey,
      }),
    (error) => error.message === "UPLOAD_KEY_INVALID",
  );

  assert.deepEqual(
    core.normalizeCloudConfig({
      spreadsheetSource: ` ${spreadsheetId} `,
      uploadUrl: ` ${uploadUrl} `,
      uploadKey: ` ${uploadKey} `,
      readKey: ` ${readKey} `,
    }),
    {spreadsheetId, uploadUrl, uploadKey, readKey},
  );
});

test("buildKeyBundle produces the complete schema v2 backup", () => {
  assert.deepEqual(
    core.buildKeyBundle({spreadsheetId, uploadUrl, uploadKey, readKey}),
    {
      format: "scanpoint-key-backup",
      schema_version: 2,
      SPREADSHEET_ID: spreadsheetId,
      UPLOAD_URL: uploadUrl,
      UPLOAD_KEY: uploadKey,
      READ_KEY: readKey,
    },
  );
});

test("customizeStationArchive replaces stale config with packaged defaults", async () => {
  const zip = new JSZip();
  zip.file("scan_point.exe", "binary-placeholder");
  zip.file("nested/station.json", "stale station");
  zip.file("cloud.config", "stale cloud");
  zip.file("upload.key", "legacy key");
  zip.file("開始使用.txt", "stale readme");

  core.customizeStationArchive(
    zip,
    {
      stationId: "CP1",
      stationName: "未命名站點",
      pin: "246810",
      extraDir: "",
    },
    {spreadsheetId, uploadUrl, uploadKey, readKey},
  );

  const bytes = await zip.generateAsync({type: "nodebuffer"});
  const packaged = await JSZip.loadAsync(bytes);
  assert.ok(packaged.file("scan_point.exe"));
  assert.equal(packaged.file("nested/station.json"), null);
  assert.equal(packaged.file("upload.key"), null);

  const station = JSON.parse(await packaged.file("station.json").async("string"));
  assert.deepEqual(station, {
    station_id: "CP1",
    station_name: "未命名站點",
    pin: "246810",
    extra_dir: "",
  });

  const cloud = await packaged.file("cloud.config").async("string");
  assert.match(cloud, new RegExp(`SPREADSHEET_ID=${spreadsheetId}`));
  assert.match(cloud, new RegExp(`UPLOAD_URL=${uploadUrl}`));
  assert.match(cloud, new RegExp(`UPLOAD_KEY=${uploadKey}`));
  assert.doesNotMatch(cloud, /READ_KEY/);
  assert.match(
    await packaged.file("開始使用.txt").async("string"),
    /第一次執行 scan_point\.exe.*管理 PIN/s,
  );
});
