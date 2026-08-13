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

test("every page refreshes stale deployments and versions static assets", () => {
  for (const filename of htmlFiles) {
    const html = fs.readFileSync(path.join(webRoot, filename), "utf8");
    assert.match(html, /http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate"/);
    assert.match(html, /src="cache-refresh\.js\?v=__SCANPOINT_VERSION__"/);

    for (const match of html.matchAll(/(?:src|href)="([^"]+\.(?:js|css))(?:\?([^"]+))?"/g)) {
      assert.equal(
        match[2],
        "v=__SCANPOINT_VERSION__",
        `${filename} has an unversioned static asset: ${match[1]}`,
      );
    }
  }
});

test("score data sources have a non-overlapping OR separator", () => {
  const html = fs.readFileSync(path.join(webRoot, "score.html"), "utf8");
  const css = fs.readFileSync(path.join(webRoot, "score.css"), "utf8");
  const cloudIndex = html.indexOf("source-panel--cloud");
  const separatorIndex = html.indexOf("score-source-or");
  const localIndex = html.indexOf("source-panel--local");
  assert.ok(cloudIndex < separatorIndex && separatorIndex < localIndex);
  assert.match(html, /aria-label="或者">OR<\/div>/);
  assert.doesNotMatch(html, /score-source-or[^>]*>[\s\S]*或<\/div>/);
  assert.match(css, /grid-template-columns: minmax\(0, 1fr\) auto minmax\(0, 1fr\)/);
  assert.doesNotMatch(css.match(/\.score-source-or \{[\s\S]*?\}/)[0], /position: absolute/);
});
test("successful data loading can be reset for another upload", () => {
  const html = fs.readFileSync(path.join(webRoot, "score.html"), "utf8");
  const script = fs.readFileSync(path.join(webRoot, "score.js"), "utf8");
  assert.match(html, /id="score-source-grid"/);
  assert.match(html, /id="loaded-data-view" hidden/);
  assert.match(html, /id="loaded-station-list"/);
  assert.match(html, /辨識到的站點節點/);
  assert.match(html, /id="reload-data"[^>]*hidden>重新上傳<\/button>/);
  assert.match(script, /elements\.sourceGrid\.hidden = true/);
  assert.match(script, /elements\.loadedView\.hidden = false/);
  assert.match(script, /renderStationChips\(stations, elements\.loadedStationList, false, true\)/);
  assert.match(script, /count\.textContent = `\$\{station\.count\} 筆資料`/);
  assert.match(script, /elements\.reloadData\.hidden = false/);
  assert.match(script, /function reopenDataUpload\(\)/);
  assert.match(script, /elements\.reloadData\.addEventListener\("click", reopenDataUpload\)/);
});
test("hidden score panels always stay hidden after data is loaded", () => {
  const css = fs.readFileSync(path.join(webRoot, "score.css"), "utf8");
  assert.match(
    css,
    /\.score-app\[data-data-ready="true"\] \.score-card--data:not\(\[hidden\]\)/,
  );
  assert.doesNotMatch(
    css,
    /\.score-app\[data-data-ready="true"\] \.score-card--data\s*\{/,
  );
});

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

test("deployment mapping controls stay in their intended scopes", () => {
  const script = fs.readFileSync(path.join(webRoot, "app.js"), "utf8");
  const busyStart = script.indexOf("function setStationDownloadBusy(busy)");
  const busyEnd = script.indexOf("function downloadBlob", busyStart);
  const busyFunction = script.slice(busyStart, busyEnd);
  assert.match(busyFunction, /idMappingFile\.disabled = busy/);
  assert.match(busyFunction, /clearIdMapping\.disabled = busy/);

  const offlineStart = script.indexOf("async function downloadOfflinePackage");
  const listenerStart = script.indexOf(
    'elements.idMappingFile.addEventListener("change"',
  );
  const keyListenerStart = script.indexOf(
    'elements.downloadKeyBundle.addEventListener("click"',
  );
  const submitStart = script.indexOf(
    'elements.stationForm.addEventListener("submit"',
  );
  assert.ok(listenerStart > keyListenerStart, "mapping listener must be registered globally");
  assert.ok(listenerStart < submitStart, "mapping listener must be registered globally");
});

test("ID mapping is an optional step between deployment and download", () => {
  const html = fs.readFileSync(path.join(webRoot, "deploy.html"), "utf8");
  const script = fs.readFileSync(path.join(webRoot, "app.js"), "utf8");
  const deployIndex = html.indexOf('id="web-app-deploy"');
  const mappingIndex = html.indexOf('id="id-mapping"');
  const downloadIndex = html.indexOf('id="station-config"');
  assert.ok(deployIndex < mappingIndex && mappingIndex < downloadIndex);
  assert.match(html, /ID 對照表[\s\S]*選用/);
  assert.match(html, /選手姓名、隊名、組別或棒次/);
  assert.match(html, /原始手環 ID/);
  assert.match(html, /href="#station-config">跳過這個步驟<\/a>/);
  assert.match(script, /offline \? "01" : "04"/);
  assert.match(script, /offline \? "02" : "05"/);
  assert.match(script, /offline \? "03" : "06"/);
});
