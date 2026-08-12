# Score Center

Reserved for a standalone importer and ranking tool.

The working implementation currently lives in the web module: the scoring rules
are in [`web/score-engine.js`](../web/score-engine.js) with tests in
[`web/tests/score-engine.test.js`](../web/tests/score-engine.test.js), and the
operator-facing page is [`web/score.html`](../web/score.html). It reads either
the station exports (`scans.jsonl` / `scans-*.csv`) or the uploaded Google
spreadsheet.

This directory stays empty on purpose. Keeping scoring out of the station
module prevents ranking logic from being coupled to unattended scan stations,
and leaves room for an offline desktop scorer without moving the rules again.
