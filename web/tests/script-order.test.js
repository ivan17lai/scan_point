"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const webRoot = path.resolve(__dirname, "..");

test("deployment core loads before the deployment UI", () => {
  const html = fs.readFileSync(path.join(webRoot, "deploy.html"), "utf8");
  assert.ok(html.indexOf("deployment-core.js") < html.indexOf("app.js"));
});

test("score modules load before the score UI", () => {
  const html = fs.readFileSync(path.join(webRoot, "score.html"), "utf8");
  assert.ok(html.indexOf("score-engine.js") < html.indexOf("score.js"));
  assert.ok(html.indexOf("score-config.js") < html.indexOf("score.js"));
});
