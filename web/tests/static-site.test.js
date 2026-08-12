"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const webRoot = path.resolve(__dirname, "..");
const htmlFiles = fs.readdirSync(webRoot).filter((name) => name.endsWith(".html"));

for (const filename of htmlFiles) {
  test(`${filename} has unique IDs and valid local links`, () => {
    const html = fs.readFileSync(path.join(webRoot, filename), "utf8");
    const ids = Array.from(html.matchAll(/\bid="([^"]+)"/g), (match) => match[1]);
    assert.equal(new Set(ids).size, ids.length, "duplicate HTML id");

    for (const match of html.matchAll(/href="([^"#][^"]*)"/g)) {
      const target = match[1].split(/[?#]/)[0];
      if (!target || /^(?:https?:|mailto:)/.test(target)) continue;
      assert.ok(fs.existsSync(path.join(webRoot, target)), `missing local link: ${target}`);
    }

    for (const match of html.matchAll(/(?:src|href)="([^"?#]+\.(?:js|css))[^\"]*"/g)) {
      assert.ok(
        fs.existsSync(path.join(webRoot, match[1])),
        `missing local asset: ${match[1]}`,
      );
    }
  });
}

test("every direct ID selector used by page scripts exists in its HTML", () => {
  for (const [scriptName, htmlName] of [
    ["app.js", "deploy.html"],
    ["score.js", "score.html"],
  ]) {
    const script = fs.readFileSync(path.join(webRoot, scriptName), "utf8");
    const html = fs.readFileSync(path.join(webRoot, htmlName), "utf8");
    const ids = new Set(
      Array.from(html.matchAll(/\bid="([^"]+)"/g), (match) => match[1]),
    );
    for (const match of script.matchAll(/querySelector\("#([^"]+)"\)/g)) {
      assert.ok(ids.has(match[1]), `${scriptName} references missing #${match[1]}`);
    }
  }
});
