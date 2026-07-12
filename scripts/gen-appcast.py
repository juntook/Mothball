#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Generate a single-entry Sparkle appcast for a released dmg.

The app ships without SUPublicEDKey, so Sparkle validates updates via the
Developer ID code signature of the downloaded archive (HTTPS + same team).

Usage: gen-appcast.py <dmg-path> <short-version> <build-version> <download-url>
Prints the appcast XML to stdout.
"""
import os
import sys
from datetime import datetime, timezone
from xml.sax.saxutils import escape

def main() -> int:
    if len(sys.argv) != 5:
        print(__doc__, file=sys.stderr)
        return 2
    dmg, short_version, build_version, url = sys.argv[1:]
    size = os.path.getsize(dmg)
    pub_date = datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S +0000")
    print(f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Mothball</title>
    <item>
      <title>Version {escape(short_version)}</title>
      <pubDate>{pub_date}</pubDate>
      <sparkle:version>{escape(build_version)}</sparkle:version>
      <sparkle:shortVersionString>{escape(short_version)}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <enclosure url="{escape(url)}" length="{size}" type="application/octet-stream"/>
    </item>
  </channel>
</rss>""")
    return 0

if __name__ == "__main__":
    sys.exit(main())
