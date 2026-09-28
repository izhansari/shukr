#!/usr/bin/env python3
"""shukr/WhatsNew.json helper (see CLAUDE.md "What's new").

The file has two lists: `topics` (one card each: id, area, a title that describes the CURRENT
state, optional current try-it steps) and `entries` (one per visible change, chronological:
a stable `id` ("<topic>-<n>", never changes, even if the title is edited), date, commit, time,
topic, notes item, one-line title, try-it steps, checked, optional status "dropped" /
"replaced" / "removed", optional screenshots).

  scripts/whatsnew.py resolve
      Fill in "commit": "next" with the hash of the commit that added the entry, and every
      committed entry's "time" (commit time, from git). Run it before committing.

  scripts/whatsnew.py add --topic ID --title "…" --try "…" [--try "…"] [--notes "#17"]
                          [--area Zikr --topic-title "…" --topic-summary "…"] [--topic-try "…"]…
                          [--shot wn-x.jpg]… [--checked sim|phone|no] [--status dropped|replaced|removed]
                          [--topic-link salah|zikr|settings|history|azkar|map|names|ayah|insights]
                          [--addresses <feedback id>]… [--asked "<the owner's words>"] [--no-try]
      Append an entry ("commit": "next"). A new topic needs --area and --topic-title.
      --topic-title is SHORT (≤ 60 chars, e.g. "Prayers widget"); the long description of the feature
      as it is now goes in --topic-summary (shown in the detail).
      Every entry needs its own --try steps for THIS change; --no-try only for invisible changes.
      --addresses: feedback this change fixes (the app shows it under "To check").
      --asked: the owner's own request from chat (relayed by Bradley, in his words) — the app shows
      "You asked in chat: '…'" and puts the change under "To check" like addressed feedback.

  scripts/whatsnew.py asked --entry <entry id> --text "<the owner's words>"
      Set an existing entry's chat request (backfill).

  scripts/whatsnew.py address --entry <entry id> --feedback <id> [--feedback <id>]…
      Add feedback ids to an existing entry's "addresses" (e.g. a fix committed earlier).

  scripts/whatsnew.py status --entry <entry id> --set dropped|replaced|removed
      Mark an older change as undone / replaced (shown greyed).

  scripts/whatsnew.py shot <screenshot.png> <name>
      Save a small JPEG (≤ 600 px wide) as shukr/WhatsNewShots/wn-<name>.jpg and print the name
      to pass as --shot.

  scripts/whatsnew.py testflight --since <commit> [--out notes.txt]
      The TestFlight "What to Test" text for every entry after <commit> (≤ 4000 chars, no emoji),
      ready for `scripts/asc.py release <build> notes.txt`.
"""
import argparse, datetime, json, re, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FILE = ROOT / "shukr" / "WhatsNew.json"
SHOTS = ROOT / "shukr" / "WhatsNewShots"


def load():
    return json.loads(FILE.read_text())


def git(*args):
    return subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True, text=True).stdout.strip()


def j(v):
    return json.dumps(v, ensure_ascii=False)


def save(data):
    """Compact, diff-friendly layout: one topic per line or two, an entry in four lines."""
    out = ["{", '  "topics": [']
    for i, t in enumerate(data["topics"]):
        head = f'    {{"id": {j(t["id"])}, "area": {j(t["area"])}, "title": {j(t["title"])}'
        if t.get("link"):
            head += f', "link": {j(t["link"])}'
        if t.get("summary"):
            head += f',\n     "summary": {j(t["summary"])}'
        if t.get("tryIt"):
            head += f',\n     "tryIt": {j(t["tryIt"])}'
        out.append(head + "}" + ("," if i < len(data["topics"]) - 1 else ""))
    out += ["  ],", '  "entries": [']
    for i, e in enumerate(data["entries"]):
        first = f'"id": {j(e["id"])}, "date": {j(e["date"])}, "commit": {j(e["commit"])}, "time": {j(e.get("time"))}, ' \
                f'"topic": {j(e["topic"])}, "notes": {j(e.get("notes"))}'
        if e.get("status"):
            first += f', "status": {j(e["status"])}'
        last = f'"checked": {j(e["checked"])}'
        if e.get("shots"):
            last += f', "shots": {j(e["shots"])}'
        if e.get("addresses"):
            last += f', "addresses": {j(e["addresses"])}'
        if e.get("asked"):
            last += f', "asked": {j(e["asked"])}'
        out += ["    {",
                f"      {first},",
                f'      "title": {j(e["title"])},',
                f'      "tryIt": {j(e["tryIt"])},',
                f"      {last}",
                "    }" + ("," if i < len(data["entries"]) - 1 else "")]
    out += ["  ]", "}", ""]
    text = "\n".join(out)
    json.loads(text)  # still valid
    FILE.write_text(text)


def resolve():
    data = load()
    hashes_filled = times_filled = 0
    for e in data["entries"]:
        if e["commit"] == "next":
            # The oldest commit whose diff added this entry's id (stable; titles can be edited).
            found = git("log", "--format=%h", "--reverse", "-S", f'"id": {j(e["id"])}', "--", "shukr/WhatsNew.json").split()
            if found:
                e["commit"] = found[0]
                hashes_filled += 1
        if e["commit"] != "next" and not e.get("time"):
            iso = git("show", "-s", "--format=%cI", e["commit"])
            if iso:
                e["time"] = iso
                times_filled += 1
    save(data)
    print(f"resolved {hashes_filled} commit(s), {times_filled} time(s)")


TITLE_MAX = 60


def add(a):
    if a.topic_title and len(a.topic_title) > TITLE_MAX:
        sys.exit(f"--topic-title is {len(a.topic_title)} chars: keep it short (≤ {TITLE_MAX}, e.g. \"Prayers widget\") "
                 "and put the description in --topic-summary")
    if not a.tryit and not a.no_try:
        sys.exit("every entry needs its own --try steps for this change (or --no-try for an invisible one)")
    data = load()
    topics = {t["id"]: t for t in data["topics"]}
    t = topics.get(a.topic)
    if t is None:
        if not (a.area and a.topic_title):
            sys.exit(f"new topic {a.topic!r}: pass --area and --topic-title")
        t = {"id": a.topic, "area": a.area, "title": a.topic_title}
        data["topics"].append(t)
    else:
        if a.topic_title:
            t["title"] = a.topic_title
        if a.area:
            t["area"] = a.area
    if a.topic_summary:
        t["summary"] = a.topic_summary
    if a.topic_try:
        t["tryIt"] = a.topic_try
    if a.topic_link:
        t["link"] = a.topic_link
    # Keep key order stable in the file.
    for k in ("summary", "tryIt"):
        if k in t:
            t[k] = t.pop(k)
    for s in a.shot or []:
        if not (SHOTS / s).exists():
            sys.exit(f"no screenshot {SHOTS / s} (make it with `whatsnew.py shot`)")
    used = {x["id"] for x in data["entries"]}
    n = 1
    while f"{a.topic}-{n}" in used:
        n += 1
    e = {"id": f"{a.topic}-{n}", "date": datetime.date.today().isoformat(), "commit": "next", "time": None, "topic": a.topic,
         "notes": a.notes, "title": a.title, "tryIt": a.tryit or [], "checked": a.checked}
    if a.status:
        e["status"] = a.status
    if a.shot:
        e["shots"] = a.shot
    if a.addresses:
        e["addresses"] = [x.upper() for x in a.addresses]
    if a.asked:
        e["asked"] = a.asked
    data["entries"].append(e)
    save(data)
    print(f"added to {a.topic}: {a.title}")


def address(entry_id, ids):
    data = load()
    e = next((x for x in data["entries"] if x["id"] == entry_id), None)
    if e is None:
        sys.exit(f"no entry {entry_id!r}")
    have = e.setdefault("addresses", [])
    for i in ids:
        if i.upper() not in have:
            have.append(i.upper())
    save(data)
    print(f"{entry_id} addresses {', '.join(have)}")


def set_asked(entry_id, text):
    data = load()
    e = next((x for x in data["entries"] if x["id"] == entry_id), None)
    if e is None:
        sys.exit(f"no entry {entry_id!r}")
    e["asked"] = text
    save(data)
    print(f"{entry_id} asked: {text}")


def set_status(entry_id, status):
    data = load()
    e = next((x for x in data["entries"] if x["id"] == entry_id), None)
    if e is None:
        sys.exit(f"no entry {entry_id!r}")
    e["status"] = status
    save(data)
    print(f"{entry_id}: {status}")


def shot(png, name):
    SHOTS.mkdir(exist_ok=True)
    out = SHOTS / f"wn-{name}.jpg"
    subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", "55", "-Z", "600", png, "--out", str(out)],
                   check=True, capture_output=True)
    total = sum(p.stat().st_size for p in SHOTS.glob("*.jpg"))
    print(out.name)
    print(f"({out.stat().st_size // 1024} KB; all screenshots {total // 1024} KB)", file=sys.stderr)


EMOJI = re.compile("[\U00010000-\U0010FFFF☀-➿⬀-⯿️]")


def clean(s):
    return EMOJI.sub("", s).replace("☰", "the menu").strip()


def testflight(since, out):
    data = load()
    entries = data["entries"]
    topics = {t["id"]: t for t in data["topics"]}
    idx = max((i for i, e in enumerate(entries) if e["commit"] == since), default=-1)
    if idx >= 0:
        new = entries[idx + 1:]
    else:
        # A commit with no entries of its own (e.g. a build): everything not already in it.
        def in_since(c):
            return c != "next" and subprocess.run(
                ["git", "-C", str(ROOT), "merge-base", "--is-ancestor", c, since]).returncode == 0
        new = [e for e in entries if not in_since(e["commit"])]
    # One line per topic, as it is now (dropped changes don't go to testers).
    order = []
    for e in new:
        if e.get("status") in ("dropped", "replaced") or e["topic"] in order:
            continue
        order.append(e["topic"])
    areas = {}
    for tid in order:
        t = topics[tid]
        latest = [e for e in entries if e["topic"] == tid and not e.get("status")]
        steps = t.get("tryIt") or (latest[-1]["tryIt"] if latest else [])
        areas.setdefault(t["area"], []).append((t["title"], steps))
    lines = ["What's new since the last build. Thank you for testing!", ""]
    for area, items in areas.items():
        lines.append(area.upper())
        for title, steps in items:
            lines.append(f"- {clean(title)}")
            for step in steps:
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
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "resolve":
        resolve()
    elif cmd == "add":
        p = argparse.ArgumentParser(prog="whatsnew.py add")
        p.add_argument("--topic", required=True)
        p.add_argument("--title", required=True)
        p.add_argument("--try", dest="tryit", action="append")
        p.add_argument("--no-try", action="store_true", help="an invisible change: no try-it steps")
        p.add_argument("--asked", help="the owner's request from chat, in his words")
        p.add_argument("--topic-summary", help="the feature as it is now, long form (the detail)")
        p.add_argument("--notes")
        p.add_argument("--area")
        p.add_argument("--topic-title")
        p.add_argument("--topic-try", action="append")
        p.add_argument("--topic-link", choices=["salah", "zikr", "settings", "history", "azkar", "map", "names", "ayah", "insights"],
                       help="where What's new's \"Open in shukr\" goes")
        p.add_argument("--shot", action="append")
        p.add_argument("--checked", default="sim", choices=["sim", "phone", "no"])
        p.add_argument("--status", choices=["dropped", "replaced", "removed"])
        p.add_argument("--addresses", action="append", help="a feedback id this change fixes")
        add(p.parse_args(sys.argv[2:]))
    elif cmd == "address":
        p = argparse.ArgumentParser(prog="whatsnew.py address")
        p.add_argument("--entry", required=True)
        p.add_argument("--feedback", action="append", required=True)
        a = p.parse_args(sys.argv[2:])
        address(a.entry, a.feedback)
    elif cmd == "asked":
        p = argparse.ArgumentParser(prog="whatsnew.py asked")
        p.add_argument("--entry", required=True)
        p.add_argument("--text", required=True)
        a = p.parse_args(sys.argv[2:])
        set_asked(a.entry, a.text)
    elif cmd == "status":
        p = argparse.ArgumentParser(prog="whatsnew.py status")
        p.add_argument("--entry", required=True)
        p.add_argument("--set", required=True, choices=["dropped", "replaced", "removed"])
        a = p.parse_args(sys.argv[2:])
        set_status(a.entry, a.set)
    elif cmd == "shot" and len(sys.argv) == 4:
        shot(sys.argv[2], sys.argv[3])
    elif cmd == "testflight" and len(sys.argv) >= 4 and sys.argv[2] == "--since":
        testflight(sys.argv[3], sys.argv[5] if len(sys.argv) >= 6 and sys.argv[4] == "--out" else None)
    else:
        print(__doc__)
