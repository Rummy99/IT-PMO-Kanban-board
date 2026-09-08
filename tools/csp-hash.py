#!/usr/bin/env python3
"""Regenerate the CSP hashes in index.html.

The Content-Security-Policy meta tag pins the inline <style> and <script>
blocks by SHA-256. Editing either block invalidates its hash, and the page
then loads with no styling and no behaviour -- silently, with the reason only
visible in the browser console. Run this after any edit to those blocks:

    python3 tools/csp-hash.py            # rewrite index.html in place
    python3 tools/csp-hash.py --check    # verify only; exit 1 if stale (CI-friendly)

Note the extraction is anchored to column 0. The CSP comment inside <head>
mentions script and style tags in prose, and a loose regex happily matches
those instead of the real blocks -- which produces plausible-looking hashes
that break the page.
"""

import argparse
import base64
import hashlib
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
TARGET = ROOT / "index.html"


def extract(html, tag):
    """Return the exact text node between <tag> and </tag>, newlines included.

    CSP hashes the text node verbatim, so the newline immediately after the
    opening tag and the one before the closing tag are part of the digest.
    """
    match = re.search(r"^<%s>\n(.*?)\n^</%s>" % (tag, tag), html, re.S | re.M)
    if not match:
        sys.exit("error: no top-level <%s> block found in %s" % (tag, TARGET.name))
    body = match.group(1)
    if "<%s>" % tag in body:
        sys.exit("error: <%s> extraction is contaminated -- check the CSP comment" % tag)
    return "\n" + body + "\n"


def digest(text):
    return "sha256-" + base64.b64encode(hashlib.sha256(text.encode()).digest()).decode()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true",
                        help="report staleness without writing; exit 1 if stale")
    args = parser.parse_args()

    html = TARGET.read_text()
    wanted = {"script": digest(extract(html, "script")),
              "style": digest(extract(html, "style"))}

    stale = []
    for kind, value in wanted.items():
        current = re.search(r"%s-src '(sha256-[^']+)'" % kind, html)
        if not current:
            sys.exit("error: no %s-src hash found in the CSP meta tag" % kind)
        if current.group(1) != value:
            stale.append(kind)

    if not stale:
        print("CSP hashes are current.")
        return 0

    if args.check:
        print("STALE: " + ", ".join(stale) + " hash(es) do not match index.html.")
        print("Run: python3 tools/csp-hash.py")
        return 1

    for kind, value in wanted.items():
        html = re.sub(r"%s-src 'sha256-[^']+'" % kind, "%s-src '%s'" % (kind, value), html)
    TARGET.write_text(html)
    print("Updated: " + ", ".join(stale))
    for kind, value in wanted.items():
        print("  %-6s %s" % (kind, value))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
