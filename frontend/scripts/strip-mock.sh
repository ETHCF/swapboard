#!/bin/sh
# Removes mock mode from a built frontend: deletes mock.js, and drops its
# <script> tag and its row in the build-verification modal from index.html.
# Every build runs this when DISABLE_MOCK=1, so ?mock=true has nothing to load.
#
#   sh frontend/scripts/strip-mock.sh <dist-dir>
set -eu

DIST="${1:?usage: strip-mock.sh <dist-dir>}"

rm -f "$DIST/mock.js"

# The verify rows are flat <div class="verify-row">...</div> blocks, so each is
# buffered to its closing tag and dropped if it names mock.js.
awk '
  /<script src="mock.js"><\/script>/ { next }
  /<div class="verify-row">/ { buf = $0; held = 1; next }
  held {
    buf = buf "\n" $0
    if ($0 ~ /<\/div>/) {
      if (buf !~ /verify-file">mock\.js</) print buf
      held = 0
    }
    next
  }
  { print }
' "$DIST/index.html" > "$DIST/index.html.tmp"
mv "$DIST/index.html.tmp" "$DIST/index.html"

if grep -q "mock\.js" "$DIST/index.html"; then
  echo "strip-mock.sh: index.html still references mock.js" >&2
  exit 1
fi
echo "Mock mode stripped from $DIST"
