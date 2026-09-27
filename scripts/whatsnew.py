#!/usr/bin/env python3
"""shukr/WhatsNew.json helper (see CLAUDE.md "What's new").

  scripts/whatsnew.py resolve
      Replace every "commit": "next" with the short hash of the commit that added that entry.
      Run it before committing; then add your new entries with "commit": "next".

  scripts/whatsnew.py testflight --since <commit> [--out notes.txt]
      The TestFlight "What to Test" text for every entry after <commit> (≤ 4000 chars, no emoji),
      ready for `scripts/asc.py release <build> notes.txt`.
"""
import json, re, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FILE = ROOT / "shukr" / "WhatsNew.json"


def load():
    return json.loads(FILE.read_text())


def git(*args):
    return subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True, text=True).stdout.strip()


def resolve():
    text = FILE.read_text()
    entries = json.loads(text)
    changed = 0
    for e in entries:
        if e["commit"] != "next":
            continue
        # The oldest commit whose diff added this entry's title.
        title = json.dumps(e["title"], ensure_ascii=False)[1:-1]
        hashes = git("log", "--format=%h", "--reverse", "-S", title, "--", "shukr/WhatsNew.json").split()
        if not hashes:
            continue          # not committed yet: stays "next"
        text = re.sub(r'("commit":\s*)"next"(?=[^\]]*?' + re.escape(json.dumps(e["title"], ensure_ascii=False)) + ')',
                      r'\1"' + hashes[0] + '"', text, count=1)
        changed += 1
    FILE.write_text(text)
    json.loads(text)  # still valid
    print(f"resolved {changed} entr{'y' if changed == 1 else 'ies'}")


EMOJI = re.compile("[\U00010000-\U0010FFFF☀-➿⬀-⯿️]")


def clean(s):
    return EMOJI.sub("", s).replace("☰", "the menu").strip()


def testflight(since, out):
    entries = load()
    idx = max((i for i, e in enumerate(entries) if e["commit"] == since), default=-1)
    if idx >= 0:
        new = entries[idx + 1:]
    else:
        # A commit with no entries of its own (e.g. a build): everything not already in it.
        def in_since(c):
            return c != "next" and subprocess.run(
                ["git", "-C", str(ROOT), "merge-base", "--is-ancestor", c, since]).returncode == 0
        new = [e for e in entries if not in_since(e["commit"])]
    areas = {}
    for e in new:
        areas.setdefault(e["area"], []).append(e)
    lines = ["What's new since the last build. Thank you for testing!", ""]
    for area, items in areas.items():
        lines.append(area.upper())
        for e in items:
            lines.append(f"- {clean(e['title'])}")
            for step in e["tryIt"]:
                lines.append(f"  Try: {clean(step)}")
        lines.append("")
    lines.append("Found something off? Send feedback with a screenshot from TestFlight.")
    text = "\n".join(lines)
    if len(text) > 4000:
        # Keep titles, drop the try-it steps.
        text = "\n".join(l for l in lines if not l.startswith("  Try:"))[:4000]
    if out:
        Path(out).write_text(text)
    print(text)
    print(f"\n({len(text)} chars)", file=sys.stderr)


if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "resolve":
        resolve()
    elif len(sys.argv) >= 4 and sys.argv[1] == "testflight" and sys.argv[2] == "--since":
        testflight(sys.argv[3], sys.argv[5] if len(sys.argv) >= 6 and sys.argv[4] == "--out" else None)
    else:
        print(__doc__)
