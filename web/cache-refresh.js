(function () {
  "use strict";

  if (
    location.protocol === "file:" ||
    location.hostname === "localhost" ||
    location.hostname === "127.0.0.1"
  ) {
    return;
  }

  fetch(`site-version.txt?cache=${Date.now()}`, {cache: "no-store"})
    .then((response) => {
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      return response.text();
    })
    .then((text) => {
      const deployedVersion = text.trim();
      if (!deployedVersion) return;

      const currentUrl = new URL(location.href);
      if (currentUrl.searchParams.get("v") === deployedVersion) return;

      currentUrl.searchParams.set("v", deployedVersion);
      location.replace(currentUrl);
    })
    .catch(() => {
      // A refresh check must never prevent the static page from loading.
    });
})();
