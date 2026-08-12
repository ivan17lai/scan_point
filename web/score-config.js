"use strict";

(function attachScoreConfig(root, factory) {
  const config = factory();
  if (typeof module !== "undefined" && module.exports) {
    module.exports = config;
  }
  root.ScanPointScoreConfig = config;
})(typeof globalThis !== "undefined" ? globalThis : this, () => {
  const appsScriptEndpointPattern =
    /^https:\/\/script\.google\.com\/macros\/s\/[^/]+\/exec$/;

  function parseKeyBackupPayload(payload) {
    if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
      throw new Error("金鑰檔格式無效");
    }
    const uploadUrl = payload.UPLOAD_URL || payload.upload_url || payload.uploadUrl;
    const readKey = payload.READ_KEY || payload.read_key || payload.readKey;
    if (
      typeof uploadUrl !== "string" ||
      !appsScriptEndpointPattern.test(uploadUrl.trim())
    ) {
      throw new Error("UPLOAD_URL 必須是以 /exec 結尾的 Apps Script 正式網址");
    }
    if (typeof readKey !== "string" || !readKey.trim()) {
      throw new Error("檔案中找不到 READ_KEY");
    }
    return {uploadUrl: uploadUrl.trim(), readKey: readKey.trim()};
  }

  function buildScoreEndpoint(endpointText, readKey) {
    if (!appsScriptEndpointPattern.test(String(endpointText || "").trim())) {
      throw new Error("請輸入以 /exec 結尾的 Apps Script 正式網址。");
    }
    if (!String(readKey || "").trim()) throw new Error("請輸入 READ_KEY。");
    const endpoint = new URL(endpointText.trim());
    endpoint.searchParams.set("action", "scores");
    endpoint.searchParams.set("read_key", readKey.trim());
    return endpoint;
  }

  return {
    appsScriptEndpointPattern,
    buildScoreEndpoint,
    parseKeyBackupPayload,
  };
});
