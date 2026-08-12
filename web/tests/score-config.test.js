"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const config = require("../score-config.js");

const uploadUrl = "https://script.google.com/macros/s/deployment-id/exec";

test("parseKeyBackupPayload reads a complete scanpoint key file", () => {
  assert.deepEqual(
    config.parseKeyBackupPayload({
      format: "scanpoint-key-backup",
      schema_version: 2,
      UPLOAD_URL: ` ${uploadUrl} `,
      READ_KEY: " READ_KEY_1234567890 ",
    }),
    {uploadUrl, readKey: "READ_KEY_1234567890"},
  );
});

test("parseKeyBackupPayload rejects invalid files without partial values", () => {
  assert.throws(
    () => config.parseKeyBackupPayload(null),
    /金鑰檔格式無效/,
  );
  assert.throws(
    () =>
      config.parseKeyBackupPayload({
        UPLOAD_URL: "https://example.com/exec",
        READ_KEY: "READ_KEY_1234567890",
      }),
    /Apps Script 正式網址/,
  );
  assert.throws(
    () => config.parseKeyBackupPayload({UPLOAD_URL: uploadUrl}),
    /READ_KEY/,
  );
});

test("buildScoreEndpoint adds the scores action and read key", () => {
  const endpoint = config.buildScoreEndpoint(uploadUrl, " read-key ");
  assert.equal(endpoint.origin + endpoint.pathname, uploadUrl);
  assert.equal(endpoint.searchParams.get("action"), "scores");
  assert.equal(endpoint.searchParams.get("read_key"), "read-key");
});

test("buildScoreEndpoint rejects an invalid URL or missing key", () => {
  assert.throws(
    () => config.buildScoreEndpoint("https://example.com/exec", "read-key"),
    /Apps Script 正式網址/,
  );
  assert.throws(() => config.buildScoreEndpoint(uploadUrl, ""), /READ_KEY/);
});
