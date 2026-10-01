#!/usr/bin/env python3
"""shukr/WhatsNew.jsonl helper — What's new v4 (see CLAUDE.md "What's new").

The file is JSON Lines: one record per line, never hand-edited. Four kinds:
  topic   {"kind":"topic","id","area","title","summary"?,"link"?,"tryIt"?}      a feature (short title ≤ 60)
  ask     {"kind":"ask","id","topic","words","source":"chat"|"note","note"?,"created"}
          something the owner asked for (his words, verbatim) — the page's "Your asks"
  change  {"kind":"change","id","time","topic","title","headline","tryIt","shots"?,"asks"?,"notes"?,
           "status"?,"checked"}                                                   one visible change
  verdict {"kind":"verdict","ask","verdict":"works"|"notyet","words"?,"at","by":"chat"}
          his answer given in chat (Bradley records it; the phone's own answers live in its feedback.json)
  build   {"kind":"build","number","time","commit"}   a TestFlight upload (testflight.sh writes it) — the app's
          "Next build" lists the changes after the newest one
  decision {"kind":"decision","id","area","question","options":[{"id","label","shot"?}],"recommend"?,"why"?,"created"}
          a question for Izhan (CLAUDE.md step 8); open until a decision-answer line exists
  decision-answer {"kind":"decision-answer","decision","option","words"?,"source":"chat"|"phone"|"board","at"}
          his answer — in chat, on the What's new page or on the board, all the same record. The newest one
          counts; "option": null = he un-picked it (back to waiting)
  decision-revise {"kind":"decision-revise","decision","question"?,"options"?,"recommend"?,"why"?,"at"}
          the asker changed it (only the fields given); answers from before it no longer count — it's open again
  decision-withdraw {"kind":"decision-withdraw","decision","why"?,"at"}
          the asker withdrew it: off the waiting lists, kept as "withdrawn" (a later revise asks it again)

`.gitattributes` merges this file with `merge=union`, so two branches that both append lines merge cleanly.
New change ids get a random suffix ("apple-watch-k3f9"), so branches can't mint the same id.

  whatsnew.py decision --id ID --question "…" --area AREA --option "A|label|wn-x.jpg" --option "B|…" [--recommend A]
  whatsnew.py decision-answer ID (--option B | --clear) [--words "…"] [--source chat|phone|board]
  whatsnew.py decision-revise ID [--question "…"] [--option "A|label|wn-x.jpg"]… [--recommend A] [--why "…"]
  whatsnew.py decision-withdraw ID [--why "…"]
                  (answers from the phone come in with import-verdicts / add, from the pulled feedback.json)
  whatsnew.py add --topic ID --title "…" --headline "…" --try "…" [--try "…"] [--shot wn-x.jpg]…
                  [--ask SLUG [--ask-words "his words"] | --ask-note <feedback id>]… [--notes "#17"]
                  [--area Zikr --topic-title "…"] [--topic-summary "…"] [--topic-try "…"]… [--topic-link salah|…]
                  [--checked sim|phone|no] [--status dropped|replaced|removed] [--no-try]
      Append a change (stamped with the time now; no resolve step). A new topic needs --area and --topic-title.
      --ask: the ask this change answers. New asks are created on the spot: from chat, give --ask-words
      (Bradley's brief quotes him); from a note, --ask-note <id> (the words come from the pulled
      feedback.json; the slug is note-<first 8 of the id>). Old flags still work:
      --asked "<words>" = a new chat ask, --addresses <id> = --ask-note <id>.

  whatsnew.py edit --entry ID [--title …] [--headline …] [--try …]… [--shot …]… [--ask …]…
  whatsnew.py drop --entry ID
      Change or remove a change that isn't committed yet (refused once it's in HEAD).
  whatsnew.py status --entry ID --set dropped|replaced|removed     an older change undone / replaced (greyed)
  whatsnew.py headline --entry ID --text "…"                       backfill a headline
  whatsnew.py topic --id ID [--title …] [--area …] [--summary …] [--try …]… [--link …]
  whatsnew.py verdict --ask SLUG --works|--not-yet [--words "…"]  record an answer he gave in chat
  whatsnew.py import-verdicts        bring in Bradley's queued chat answers (../board/verdicts.jsonl)
  whatsnew.py shot <png> <name>      → shukr/WhatsNewShots/wn-<name>.jpg (≤ 600 px) and prints the name
  whatsnew.py check                  validate the file (duplicate ids, missing shots, bad lengths, unknown areas)
  whatsnew.py areas-remap            one-time: every topic's old area → AREAS (Watch → Apple Watch, …)
  whatsnew.py testflight --since <commit>|last [--out notes.txt]   TestFlight "What to Test" (≤ 4000 chars, no emoji);
                                     `last` = the newest build record's commit
  whatsnew.py build --number N [--commit <sha>] [--time <iso>]   record an upload (default: HEAD, its commit time)
  whatsnew.py convert                one-time: WhatsNew.json (v3) → WhatsNew.jsonl
"""
import argparse, datetime, glob, json, os, re, secrets, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FILE = ROOT / "shukr" / "WhatsNew.jsonl"
REL = "shukr/WhatsNew.jsonl"
OLD = ROOT / "shukr" / "WhatsNew.json"
SHOTS = ROOT / "shukr" / "WhatsNewShots"
TEAM = ROOT.parent                       # shukrGit: board/ and feedback/ sit beside every checkout
VERDICT_QUEUE = TEAM / "board" / "verdicts.jsonl"
# board/decide.sh queues decisions and answers here (Bradley doesn't write the repo); `add` and import-verdicts
# bring them in, turning each option's picture into a wn-*.jpg.
DECISION_QUEUE = TEAM / "board" / "decisions.jsonl"

TITLE_MAX = 60
HEADLINE_MAX = 40
LINKS = ["salah", "zikr", "settings", "history", "azkar", "map", "names", "ayah", "insights"]
# The page groups by these, in this order (WhatsNew.areaOrder in the app keeps the same list).
AREAS = ["Salah", "Zikr", "Apple Watch", "Widgets", "Map & Mosques", "Insights", "Daily Ayah", "99 Names",
         "Reminders", "Setup & Settings"]
# One-time: the areas before 2026-09-29 → the ones above (`areas-remap`).
AREA_REMAP = {"Watch": "Apple Watch", "Widget": "Widgets", "Map": "Map & Mosques", "Mosques": "Map & Mosques",
              "Notifications": "Reminders", "Setup": "Setup & Settings", "Settings": "Setup & Settings",
              "Welcome": "Setup & Settings", "Location": "Setup & Settings", "Beta": "Setup & Settings"}
KEY_ORDER = {
    "topic": ["kind", "id", "area", "title", "link", "summary", "tryIt"],
    "ask": ["kind", "id", "topic", "source", "note", "created", "words"],
    "change": ["kind", "id", "time", "topic", "asks", "notes", "status", "checked", "commit", "headline", "title", "tryIt", "shots"],
    "verdict": ["kind", "ask", "verdict", "at", "by", "words"],
    "build": ["kind", "number", "time", "commit"],
    "decision": ["kind", "id", "area", "created", "question", "options", "recommend", "why"],
    "decision-answer": ["kind", "decision", "option", "source", "at", "words"],
    "decision-revise": ["kind", "decision", "at", "question", "options", "recommend", "why"],
    "decision-withdraw": ["kind", "decision", "at", "why"],
}


def now():
    return datetime.datetime.now().astimezone().replace(microsecond=0).isoformat()


def git(*args):
    return subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True, text=True).stdout


# MARK: the file

def load():
    if not FILE.exists():
        sys.exit(f"no {REL} (run `whatsnew.py convert` once)")
    out = []
    for n, line in enumerate(FILE.read_text().splitlines(), 1):
        if not line.strip():
            continue
        try:
            out.append(json.loads(line))
        except json.JSONDecodeError as e:
            sys.exit(f"{REL}:{n}: not JSON ({e})")
    return out


def ordered(r):
    keys = KEY_ORDER.get(r.get("kind"), [])
    out = {k: r[k] for k in keys if k in r and r[k] not in (None, [], "")}
    for k, v in r.items():
        if k not in out and v not in (None, [], ""):
            out[k] = v
    return out


def save(records):
    text = "".join(json.dumps(ordered(r), ensure_ascii=False, separators=(", ", ": ")) + "\n" for r in records)
    for line in text.splitlines():
        json.loads(line)
    FILE.write_text(text)


def of(records, kind):
    return [r for r in records if r.get("kind") == kind]


def find(records, kind, id_):
    hits = [r for r in records if r.get("kind") == kind and r.get("id") == id_]
    return hits[-1] if hits else None


def committed_ids():
    """Change ids already in HEAD's file (edit / drop refuse those)."""
    ids = set()
    for line in git("show", f"HEAD:{REL}").splitlines():
        try:
            r = json.loads(line)
        except json.JSONDecodeError:
            continue
        if r.get("kind") == "change":
            ids.add(r.get("id"))
    return ids


# MARK: pulled feedback (a note's words)

def pulled_feedback():
    """Every note pulled from the phones (the newest copy of each id)."""
    notes = {}
    paths = sorted(glob.glob(str(TEAM / "feedback" / "*" / "feedback.json")), key=os.path.getmtime)
    for p in paths:
        try:
            for f in json.load(open(p)):
                if f.get("id"):
                    notes[f["id"].upper()] = f
        except (OSError, json.JSONDecodeError):
            pass
    return notes


def resolve_note(prefix, notes=None):
    notes = pulled_feedback() if notes is None else notes
    p = prefix.upper()
    hits = [k for k in notes if k.startswith(p)]
    return (hits[0], notes[hits[0]]) if len(hits) == 1 else (p, None)


# MARK: asks

def ensure_ask(records, slug, topic, words=None, note=None):
    """The ask with this slug; created if it's new (needs his words, or a note to take them from)."""
    a = find(records, "ask", slug)
    if a:
        if words and not a.get("words"):
            a["words"] = words
        return a
    if note:
        full, f = resolve_note(note)
        a = {"kind": "ask", "id": slug, "topic": (f or {}).get("topic") or topic, "source": "note", "note": full,
             "created": (f or {}).get("created") or now(), "words": (f or {}).get("text") or words or ""}
        if not a["words"]:
            print(f"note: no pulled note {note!r} to take the words from — the app shows the note from the phone",
                  file=sys.stderr)
    else:
        if not words:
            sys.exit(f"new ask {slug!r}: pass --ask-words \"<his words, verbatim>\" (or --ask-note <feedback id>)")
        a = {"kind": "ask", "id": slug, "topic": topic, "source": "chat", "created": now(), "words": words}
    records.append(a)
    print(f"new ask {slug}: {a['words'][:70]}")
    return a


def ask_slugs(records, a, topic):
    """The slugs this change answers, creating any new asks."""
    slugs = []
    words = list(a.ask_words or [])
    for i, slug in enumerate(a.ask or []):
        ensure_ask(records, slug, topic, words=words[i] if i < len(words) else None)
        slugs.append(slug)
    for note in (a.ask_note or []) + (a.addresses or []):
        slug = f"note-{note[:8].lower()}"
        ensure_ask(records, slug, topic, note=note)
        slugs.append(slug)
    if a.asked:
        slug = f"chat-{secrets.token_hex(2)}"
        ensure_ask(records, slug, topic, words=a.asked)
        slugs.append(slug)
    return list(dict.fromkeys(slugs))


# MARK: commands

def check_texts(title=None, headline=None, topic_title=None):
    if topic_title and len(topic_title) > TITLE_MAX:
        sys.exit(f"--topic-title is {len(topic_title)} chars: keep it ≤ {TITLE_MAX} (e.g. \"Prayers widget\"); "
                 "the long description goes in --topic-summary")
    if headline is not None and len(headline) > HEADLINE_MAX:
        sys.exit(f"--headline is {len(headline)} chars: keep it ≤ {HEADLINE_MAX}")


def upsert_topic(records, a):
    t = find(records, "topic", a.topic)
    if t is None:
        if not (a.area and a.topic_title):
            sys.exit(f"new topic {a.topic!r}: pass --area and --topic-title")
        t = {"kind": "topic", "id": a.topic, "area": a.area, "title": a.topic_title}
        records.append(t)
    for k, v in (("title", a.topic_title), ("area", a.area), ("summary", a.topic_summary), ("tryIt", a.topic_try),
                 ("link", a.topic_link)):
        if v:
            t[k] = v
    return t


def add(a):
    check_texts(a.title, a.headline, a.topic_title)
    if not a.tryit and not a.no_try:
        sys.exit("every change needs its own --try steps (or --no-try for an invisible one)")
    if not a.headline:
        sys.exit("every change needs a --headline: what changed, in a few words (≤ 40)")
    for s in a.shot or []:
        if not (SHOTS / s).exists():
            sys.exit(f"no screenshot {SHOTS / s} (make it with `whatsnew.py shot`)")
    records = load()
    upsert_topic(records, a)
    import_verdicts(records, quiet=True)
    import_decisions(records, quiet=True)
    used = {r.get("id") for r in of(records, "change")}
    cid = f"{a.topic}-{secrets.token_hex(2)}"
    while cid in used:
        cid = f"{a.topic}-{secrets.token_hex(2)}"
    e = {"kind": "change", "id": cid, "time": now(), "topic": a.topic, "asks": ask_slugs(records, a, a.topic),
         "notes": a.notes, "status": a.status, "checked": a.checked, "headline": a.headline, "title": a.title,
         "tryIt": a.tryit or [], "shots": a.shot}
    records.append(e)
    save(records)
    print(f"added {cid}: {a.headline}" + (f" (answers {', '.join(e['asks'])})" if e["asks"] else ""))


def uncommitted(records, entry_id):
    e = find(records, "change", entry_id)
    if e is None:
        sys.exit(f"no change {entry_id!r}")
    if entry_id in committed_ids():
        sys.exit(f"{entry_id} is already committed: use `status --set replaced` and add a new change instead")
    return e


def edit(a):
    check_texts(a.title, a.headline)
    records = load()
    e = uncommitted(records, a.entry)
    if a.title:
        e["title"] = a.title
    if a.headline:
        e["headline"] = a.headline
    if a.tryit:
        e["tryIt"] = a.tryit
    if a.shot:
        for s in a.shot:
            if not (SHOTS / s).exists():
                sys.exit(f"no screenshot {SHOTS / s}")
        e["shots"] = a.shot
    if a.ask or a.ask_note or a.addresses or a.asked:
        e["asks"] = ask_slugs(records, a, e["topic"])
    save(records)
    print(f"edited {a.entry}")


def drop(entry_id):
    records = load()
    e = uncommitted(records, entry_id)
    records.remove(e)
    save(records)
    print(f"dropped {entry_id}")


def set_field(entry_id, field, value, limit=None):
    if limit and len(value) > limit:
        sys.exit(f"{field} is {len(value)} chars: keep it ≤ {limit}")
    records = load()
    e = find(records, "change", entry_id)
    if e is None:
        sys.exit(f"no change {entry_id!r}")
    e[field] = value
    save(records)
    print(f"{entry_id} {field}: {value}")


def topic_cmd(a):
    check_texts(topic_title=a.title)
    records = load()
    t = find(records, "topic", a.id)
    if t is None:
        sys.exit(f"no topic {a.id!r} (a new one comes with `add --area --topic-title`)")
    for k, v in (("title", a.title), ("area", a.area), ("summary", a.summary), ("tryIt", a.tryit), ("link", a.link)):
        if v:
            t[k] = v
    save(records)
    print(f"topic {a.id} updated")


def verdict(a):
    records = load()
    if find(records, "ask", a.ask) is None:
        sys.exit(f"no ask {a.ask!r}")
    records.append({"kind": "verdict", "ask": a.ask, "verdict": "works" if a.works else "notyet", "at": now(),
                    "by": "chat", "words": a.words})
    save(records)
    print(f"{a.ask}: {'works' if a.works else 'not yet'} (from chat)")


def import_verdicts(records=None, quiet=False):
    """Bradley doesn't write the repo: he queues answers Izhan gives in chat in ../board/verdicts.jsonl
    (one {"ask","verdict","words","at"} per line); every `add`, and this command, brings new ones in."""
    standalone = records is None
    if standalone:
        records = load()
    if not VERDICT_QUEUE.exists():
        if not quiet:
            print("no queued verdicts")
        return 0
    have = {(v.get("ask"), v.get("at")) for v in of(records, "verdict")}
    asks = {a.get("id") for a in of(records, "ask")}
    added = 0
    for line in VERDICT_QUEUE.read_text().splitlines():
        try:
            q = json.loads(line)
        except json.JSONDecodeError:
            continue
        if (q.get("ask"), q.get("at")) in have or q.get("ask") not in asks or q.get("verdict") not in ("works", "notyet"):
            continue
        records.append({"kind": "verdict", "ask": q["ask"], "verdict": q["verdict"], "at": q["at"], "by": "chat",
                        "words": q.get("words")})
        have.add((q["ask"], q["at"]))
        added += 1
    if standalone:
        save(records)
    if added or not quiet:
        print(f"imported {added} chat verdict(s) from board/verdicts.jsonl")
    return added


def parse_option(text):
    """ "A|label|wn-shot.jpg" (the shot optional) → {"id","label","shot"?} """
    parts = text.split("|")
    if len(parts) < 2 or not parts[0].strip() or not parts[1].strip():
        sys.exit(f"--option needs \"ID|label[|wn-shot.jpg]\", got {text!r}")
    o = {"id": parts[0].strip(), "label": parts[1].strip()}
    if len(parts) > 2 and parts[2].strip():
        o["shot"] = parts[2].strip()
    return o


def decision(a, records=None):
    standalone = records is None
    if standalone:
        records = load()
    if find(records, "decision", a.id):
        sys.exit(f"decision {a.id!r} exists already")
    options = [parse_option(o) for o in a.option]
    if len(options) < 2:
        sys.exit("a decision needs at least two --option")
    ids = [o["id"] for o in options]
    if len(set(ids)) != len(ids):
        sys.exit("option ids must differ")
    if a.recommend and a.recommend not in ids:
        sys.exit(f"--recommend {a.recommend!r} isn't one of {ids}")
    for o in options:
        if o.get("shot") and not (SHOTS / o["shot"]).exists():
            sys.exit(f"no screenshot {SHOTS / o['shot']} (make it with `whatsnew.py shot`)")
    records.append({"kind": "decision", "id": a.id, "area": a.area, "created": getattr(a, "created", None) or now(),
                    "question": a.question, "options": options, "recommend": a.recommend, "why": a.why})
    if standalone:
        save(records)
    print(f"decision {a.id}: {a.question} ({' / '.join(ids)})")


def decision_answer(a, records=None):
    standalone = records is None
    if standalone:
        records = load()
    d = effective_decision(records, a.id)
    if not d:
        sys.exit(f"no decision {a.id!r}")
    option = None if getattr(a, "clear", False) else a.option
    if option is not None and option not in [o["id"] for o in d["options"]]:
        sys.exit(f"{a.id}: no option {option!r}")
    records.append({"kind": "decision-answer", "decision": a.id, "option": option, "source": a.source,
                    "at": getattr(a, "at", None) or now(), "words": a.words})
    if standalone:
        save(records)
    print(f"{a.id}: " + (f"answered {option}" if option else "un-picked (open again)") + f" ({a.source})")


def _ts(text):
    try:
        return datetime.datetime.fromisoformat(text)
    except (TypeError, ValueError):
        return datetime.datetime.min.replace(tzinfo=datetime.timezone.utc)


def effective_decision(records, did):
    """The decision as revised (each decision-revise line's fields over it, in order), or None."""
    base = find(records, "decision", did)
    if not base:
        return None
    d = dict(base)
    for r in sorted((r for r in of(records, "decision-revise") if r.get("decision") == did), key=lambda r: _ts(r.get("at"))):
        for k in ("question", "options", "recommend", "why"):
            if r.get(k) is not None:
                d[k] = r[k]
        d["revised_at"] = r.get("at")
    return d


def decision_state(records, did):
    """'open', 'answered' or 'withdrawn' (the app's rule: newest answer since the last revision counts;
    an un-pick is open; a withdrawal after the last revision is withdrawn)."""
    d = effective_decision(records, did)
    since = _ts(d.get("revised_at")) if d and d.get("revised_at") else _ts(None)
    withdrawals = [_ts(w.get("at")) for w in of(records, "decision-withdraw") if w.get("decision") == did]
    if withdrawals and max(withdrawals) > since:
        return "withdrawn"
    answers = [r for r in of(records, "decision-answer") if r.get("decision") == did and _ts(r.get("at")) > since]
    if not answers:
        return "open"
    newest = max(answers, key=lambda r: _ts(r.get("at")))
    return "answered" if newest.get("option") else "open"


def decision_revise(a, records=None):
    standalone = records is None
    if standalone:
        records = load()
    d = effective_decision(records, a.id)
    if not d:
        sys.exit(f"no decision {a.id!r}")
    line = {"kind": "decision-revise", "decision": a.id, "at": getattr(a, "at", None) or now()}
    if a.question:
        line["question"] = a.question
    if a.option:
        options = [parse_option(o) for o in a.option]
        ids = [o["id"] for o in options]
        if len(options) < 2 or len(set(ids)) != len(ids):
            sys.exit("--option: at least two, with different ids (they replace the whole list)")
        for o in options:
            if o.get("shot") and not (SHOTS / o["shot"]).exists():
                sys.exit(f"no screenshot {SHOTS / o['shot']}")
        line["options"] = options
    if a.recommend:
        ids = [o["id"] for o in line.get("options", d["options"])]
        if a.recommend not in ids:
            sys.exit(f"--recommend {a.recommend!r} isn't one of {ids}")
        line["recommend"] = a.recommend
    if a.why:
        line["why"] = a.why
    if len(line) == 3:
        sys.exit("nothing to revise: give --question, --option, --recommend or --why")
    records.append(line)
    if standalone:
        save(records)
    print(f"{a.id}: revised (open again)")


def decision_withdraw(a, records=None):
    standalone = records is None
    if standalone:
        records = load()
    if not find(records, "decision", a.id):
        sys.exit(f"no decision {a.id!r}")
    records.append({"kind": "decision-withdraw", "decision": a.id, "at": getattr(a, "at", None) or now(), "why": a.why})
    if standalone:
        save(records)
    print(f"{a.id}: withdrawn")


def import_decisions(records=None, quiet=False):
    """board/decisions.jsonl (from board/decide.sh): {"type":"ask", id, area, question, options:[{id,label,png?}],
    recommend?, why?, at} and {"type":"answer", id, option, words?, source, at} — each brought in once."""
    standalone = records is None
    if standalone:
        records = load()
    added = 0
    for line in (DECISION_QUEUE.read_text().splitlines() if DECISION_QUEUE.exists() else []):
        try:
            q = json.loads(line)
        except json.JSONDecodeError:
            continue
        if q.get("type") == "ask" and q.get("id") and not find(records, "decision", q["id"]):
            opts = []
            for o in q.get("options", []):
                spec = f"{o['id']}|{o['label']}"
                if o.get("png") and Path(o["png"]).exists():
                    name = f"decision-{q['id']}-{o['id']}".lower()
                    shot(o["png"], name)
                    spec += f"|wn-{name}.jpg"
                elif o.get("shot"):
                    spec += f"|{o['shot']}"
                opts.append(spec)
            decision(argparse.Namespace(id=q["id"], area=q.get("area"), question=q.get("question", ""), option=opts,
                                        recommend=q.get("recommend"), why=q.get("why"), created=q.get("at")), records)
            added += 1
        elif q.get("type") == "answer" and find(records, "decision", q.get("id")):
            done = {(r.get("decision"), r.get("at")) for r in of(records, "decision-answer")}
            if (q["id"], q.get("at")) in done:
                continue
            clear = q.get("option") in (None, "", "clear", "none")
            decision_answer(argparse.Namespace(id=q["id"], option=None if clear else q.get("option"), clear=clear,
                                               words=q.get("words"), source=q.get("source", "chat"), at=q.get("at")), records)
            added += 1
        elif q.get("type") == "withdraw" and find(records, "decision", q.get("id")):
            if any(w.get("decision") == q["id"] and w.get("at") == q.get("at") for w in of(records, "decision-withdraw")):
                continue
            decision_withdraw(argparse.Namespace(id=q["id"], why=q.get("why"), at=q.get("at")), records)
            added += 1
        elif q.get("type") == "revise" and find(records, "decision", q.get("id")):
            if any(r.get("decision") == q["id"] and r.get("at") == q.get("at") for r in of(records, "decision-revise")):
                continue
            opts = None
            if q.get("options"):
                opts = []
                for o in q["options"]:
                    spec = f"{o['id']}|{o['label']}"
                    if o.get("png") and Path(o["png"]).exists():
                        name = f"decision-{q['id']}-{o['id']}-r".lower()
                        shot(o["png"], name)
                        spec += f"|wn-{name}.jpg"
                    elif o.get("shot"):
                        spec += f"|{o['shot']}"
                    opts.append(spec)
            decision_revise(argparse.Namespace(id=q["id"], question=q.get("question"), option=opts,
                                               recommend=q.get("recommend"), why=q.get("why"), at=q.get("at")), records)
            added += 1
    # His answers on the phone's Decisions page, once pulled (pull-feedback.sh): FeedbackItem kind "decision".
    known = {(r.get("decision"), r.get("at")) for r in of(records, "decision-answer")}
    for item in pulled_feedback().values():
        if item.get("kind") != "decision":
            continue
        d = find(records, "decision", item.get("decision"))
        at = item.get("updated") or item.get("created")
        if not d or not at or (item["decision"], at) in known:
            continue
        option = item.get("option")   # None = he un-picked it on the phone
        if option is not None and option not in [o["id"] for o in (effective_decision(records, item["decision"]) or d).get("options") or []]:
            continue
        decision_answer(argparse.Namespace(id=item["decision"], option=option, clear=option is None,
                                           words=item.get("text") or None, source="phone", at=at), records)
        known.add((item["decision"], at))
        added += 1
    if standalone:
        save(records)
    if added or not quiet:
        print(f"imported {added} decision line(s) (board/decisions.jsonl and the phones' answers)")
    return added


def shot(png, name):
    SHOTS.mkdir(exist_ok=True)
    out = SHOTS / f"wn-{name}.jpg"
    subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", "55", "-Z", "600", png, "--out", str(out)],
                   check=True, capture_output=True)
    total = sum(p.stat().st_size for p in SHOTS.glob("*.jpg"))
    print(out.name)
    print(f"({out.stat().st_size // 1024} KB; all screenshots {total // 1024} KB)", file=sys.stderr)


def check():
    records = load()
    problems = []
    seen = {}
    for r in records:
        if r.get("kind") in ("topic", "ask", "change", "decision"):
            key = (r["kind"], r.get("id"))
            if key in seen and seen[key] != r:
                problems.append(f"two different {r['kind']} lines for {r.get('id')!r} (a union merge kept both: keep one)")
            seen[key] = r
    topics = {t["id"] for t in of(records, "topic")}
    asks = {a["id"] for a in of(records, "ask")}
    for e in of(records, "change"):
        if e.get("topic") not in topics:
            problems.append(f"{e['id']}: unknown topic {e.get('topic')!r}")
        for s in e.get("shots") or []:
            if not (SHOTS / s).exists():
                problems.append(f"{e['id']}: missing screenshot {s}")
        for s in e.get("asks") or []:
            if s not in asks:
                problems.append(f"{e['id']}: unknown ask {s!r}")
        if e.get("headline") and len(e["headline"]) > HEADLINE_MAX:
            problems.append(f"{e['id']}: headline over {HEADLINE_MAX} chars")
    for t in of(records, "topic"):
        if len(t.get("title", "")) > TITLE_MAX:
            problems.append(f"topic {t['id']}: title over {TITLE_MAX} chars")
        if t.get("area") not in AREAS:
            problems.append(f"topic {t['id']}: unknown area {t.get('area')!r} (one of: {', '.join(AREAS)})")
    for v in of(records, "verdict"):
        if v.get("ask") not in asks:
            problems.append(f"verdict for unknown ask {v.get('ask')!r}")
    decisions = {d.get("id"): d for d in of(records, "decision")}
    for d in decisions.values():
        if d.get("area") not in AREAS:
            problems.append(f"decision {d.get('id')}: unknown area {d.get('area')!r}")
        opts = [o.get("id") for o in d.get("options") or []]
        if len(opts) < 2:
            problems.append(f"decision {d.get('id')}: needs at least two options")
        if d.get("recommend") and d["recommend"] not in opts:
            problems.append(f"decision {d.get('id')}: recommends an option it doesn't have")
        for o in d.get("options") or []:
            if o.get("shot") and not (SHOTS / o["shot"]).exists():
                problems.append(f"decision {d.get('id')}: missing screenshot {o['shot']}")
    for r in of(records, "decision-answer"):
        d = decisions.get(r.get("decision"))
        if d is None:
            problems.append(f"answer for unknown decision {r.get('decision')!r}")
            continue
        # Any version's options (an answer can predate a revision); null = un-picked.
        known = {o.get("id") for o in d.get("options") or []}
        for rv in of(records, "decision-revise"):
            if rv.get("decision") == d.get("id"):
                known |= {o.get("id") for o in rv.get("options") or []}
        if r.get("option") is not None and r.get("option") not in known:
            problems.append(f"answer for {r.get('decision')}: unknown option {r.get('option')!r}")
    for r in of(records, "decision-revise") + of(records, "decision-withdraw"):
        if r.get("decision") not in decisions:
            problems.append(f"{r.get('kind')} for unknown decision {r.get('decision')!r}")
    numbers = [b.get("number") for b in of(records, "build")]
    for b in of(records, "build"):
        if not isinstance(b.get("number"), int) or not b.get("time") or not b.get("commit"):
            problems.append(f"build record needs number / time / commit: {b}")
    if len(numbers) != len(set(numbers)):
        problems.append("a build number is recorded twice")
    print(", ".join(f"{len(of(records, k))} {k}s" for k in ("topic", "ask", "change", "verdict", "build", "decision",
                                                            "decision-answer", "decision-revise", "decision-withdraw")))
    open_d = [i for i in decisions if decision_state(records, i) == "open"]
    if open_d:
        print("open decisions: " + ", ".join(open_d))
    for p in problems:
        print("✗ " + p)
    if problems:
        sys.exit(1)
    print("✓ ok")


EMOJI = re.compile("[\U00010000-\U0010FFFF☀-➿⬀-⯿️]")


def areas_remap():
    records = load()
    moved = 0
    for t in of(records, "topic"):
        new = AREA_REMAP.get(t.get("area"), t.get("area"))
        if new != t.get("area"):
            t["area"] = new
            moved += 1
    save(records)
    left = sorted({t.get("area") for t in of(records, "topic")} - set(AREAS), key=str)
    print(f"{moved} topic(s) moved" + (f"; not in AREAS: {left}" if left else ""))


def clean(s):
    return EMOJI.sub("", s.replace("☰", "the menu")).strip()


def ids_at(commit):
    """Change ids in the file as of a commit (before the switch: v3's WhatsNew.json)."""
    ids = set()
    for line in git("show", f"{commit}:{REL}").splitlines():
        try:
            r = json.loads(line)
            if r.get("kind") == "change":
                ids.add(r["id"])
        except json.JSONDecodeError:
            pass
    old = git("show", f"{commit}:shukr/WhatsNew.json")
    if old:
        try:
            ids |= {e["id"] for e in json.loads(old).get("entries", []) if e.get("id")}
        except json.JSONDecodeError:
            pass
    return ids


def last_build(records):
    builds = of(records, "build")
    return max(builds, key=lambda b: (b.get("time", ""), b.get("number", 0))) if builds else None


def build(number, commit=None, time=None):
    records = load()
    if any(b.get("number") == number for b in of(records, "build")):
        sys.exit(f"build {number} is already recorded")
    sha = (git("rev-parse", "--short", commit or "HEAD").strip())
    if not sha:
        sys.exit(f"unknown commit {commit!r}")
    when = time or git("show", "-s", "--format=%cI", sha).strip() or now()
    records.append({"kind": "build", "number": number, "time": when, "commit": sha})
    save(records)
    print(f"build {number} recorded: {sha} at {when}")


def testflight(since, out):
    records = load()
    if since == "last":
        b = last_build(records)
        if not b:
            sys.exit("no build recorded yet (whatsnew.py build --number N --commit <sha>)")
        since = b["commit"]
    topics = {t["id"]: t for t in of(records, "topic")}
    before = ids_at(since)
    changes = of(records, "change")
    order = []
    for e in changes:
        if e["id"] in before or e.get("status") in ("dropped", "replaced") or e["topic"] in order:
            continue
        order.append(e["topic"])
    areas = {}
    for tid in order:
        t = topics.get(tid, {"title": tid, "area": "Other"})
        latest = [e for e in changes if e["topic"] == tid and not e.get("status")]
        steps = t.get("tryIt") or (latest[-1]["tryIt"] if latest else [])
        areas.setdefault(t["area"], []).append((t.get("summary") or t["title"], steps))
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
        text = "\n".join(l for l in lines if not l.startswith("  Try:"))[:4000]
    if out:
        Path(out).write_text(text)
    print(text)
    print(f"\n({len(text)} chars)", file=sys.stderr)


def convert():
    """One-time: v3's WhatsNew.json → JSON Lines. Keeps every change id (the phone's saved state is keyed by
    them) and turns `asked` / `addresses` into asks."""
    if FILE.exists():
        sys.exit(f"{REL} already exists")
    old = json.loads(OLD.read_text())
    notes = pulled_feedback()
    records = [{"kind": "topic", **t} for t in old["topics"]]
    chat = {}                      # his words (first 60 chars, normalised) → slug: one ask across entries / topics
    note_slugs = set()
    asks, changes = [], []
    for e in old["entries"]:
        slugs = []
        if e.get("asked"):
            key = re.sub(r"\s+", " ", e["asked"].strip().lower())[:60]
            if key not in chat:
                chat[key] = f"chat-{e['id']}"
                asks.append({"kind": "ask", "id": chat[key], "topic": e["topic"], "source": "chat",
                             "created": e.get("time") or e["date"], "words": e["asked"]})
            slugs.append(chat[key])
        for a in e.get("addresses") or []:
            full, f = resolve_note(a, notes)
            slug = f"note-{full[:8].lower()}"
            if slug not in note_slugs:
                note_slugs.add(slug)
                asks.append({"kind": "ask", "id": slug, "topic": (f or {}).get("topic") or e["topic"], "source": "note",
                             "note": full, "created": (f or {}).get("created") or e.get("time") or e["date"],
                             "words": (f or {}).get("text", "")})
            slugs.append(slug)
        changes.append({"kind": "change", "id": e["id"], "time": e.get("time") or (e["date"] + "T12:00:00-04:00"),
                        "topic": e["topic"], "asks": slugs, "notes": e.get("notes"), "status": e.get("status"),
                        "checked": e.get("checked"), "commit": e.get("commit") if e.get("commit") != "next" else None,
                        "headline": e.get("headline"), "title": e["title"], "tryIt": e.get("tryIt"), "shots": e.get("shots")})
    records += asks + changes
    save(records)
    print(f"converted: {len(old['topics'])} topics, {len(asks)} asks ({len(chat)} chat, {len(note_slugs)} notes), "
          f"{len(changes)} changes → {REL}")


def parser_add(prog, edit=False):
    p = argparse.ArgumentParser(prog=prog)
    if edit:
        p.add_argument("--entry", required=True)
        p.add_argument("--title")
    else:
        p.add_argument("--topic", required=True)
        p.add_argument("--title", required=True)
    p.add_argument("--headline", help="what changed, in a few words (≤ 40 chars)")
    p.add_argument("--try", dest="tryit", action="append")
    p.add_argument("--shot", action="append")
    p.add_argument("--ask", action="append", help="the ask (slug) this change answers")
    p.add_argument("--ask-words", action="append", help="a new chat ask's words, verbatim (one per --ask)")
    p.add_argument("--ask-note", action="append", help="a feedback note this change answers (its id)")
    p.add_argument("--asked", help="(old flag) a new chat ask, in his words")
    p.add_argument("--addresses", action="append", help="(old flag) = --ask-note")
    if not edit:
        p.add_argument("--no-try", action="store_true")
        p.add_argument("--notes")
        p.add_argument("--area", choices=AREAS)
        p.add_argument("--topic-title")
        p.add_argument("--topic-summary")
        p.add_argument("--topic-try", action="append")
        p.add_argument("--topic-link", choices=LINKS)
        p.add_argument("--checked", default="sim", choices=["sim", "phone", "no"])
        p.add_argument("--status", choices=["dropped", "replaced", "removed"])
    return p


if __name__ == "__main__":
    cmd, rest = (sys.argv[1], sys.argv[2:]) if len(sys.argv) > 1 else ("", [])
    if cmd == "add":
        add(parser_add("whatsnew.py add").parse_args(rest))
    elif cmd == "edit":
        edit(parser_add("whatsnew.py edit", edit=True).parse_args(rest))
    elif cmd == "drop":
        p = argparse.ArgumentParser(prog="whatsnew.py drop")
        p.add_argument("--entry", required=True)
        drop(p.parse_args(rest).entry)
    elif cmd == "status":
        p = argparse.ArgumentParser(prog="whatsnew.py status")
        p.add_argument("--entry", required=True)
        p.add_argument("--set", required=True, choices=["dropped", "replaced", "removed"])
        a = p.parse_args(rest)
        set_field(a.entry, "status", a.set)
    elif cmd == "headline":
        p = argparse.ArgumentParser(prog="whatsnew.py headline")
        p.add_argument("--entry", required=True)
        p.add_argument("--text", required=True)
        a = p.parse_args(rest)
        set_field(a.entry, "headline", a.text, HEADLINE_MAX)
    elif cmd == "topic":
        p = argparse.ArgumentParser(prog="whatsnew.py topic")
        p.add_argument("--id", required=True)
        p.add_argument("--title")
        p.add_argument("--area", choices=AREAS)
        p.add_argument("--summary")
        p.add_argument("--try", dest="tryit", action="append")
        p.add_argument("--link", choices=LINKS)
        topic_cmd(p.parse_args(rest))
    elif cmd == "verdict":
        p = argparse.ArgumentParser(prog="whatsnew.py verdict")
        p.add_argument("--ask", required=True)
        g = p.add_mutually_exclusive_group(required=True)
        g.add_argument("--works", action="store_true")
        g.add_argument("--not-yet", action="store_true")
        p.add_argument("--words")
        verdict(p.parse_args(rest))
    elif cmd == "import-verdicts":
        records = load()
        import_verdicts(records)
        import_decisions(records)
        save(records)
    elif cmd == "decision":
        p = argparse.ArgumentParser(prog="whatsnew.py decision")
        p.add_argument("--id", required=True)
        p.add_argument("--question", required=True)
        p.add_argument("--area", required=True, choices=AREAS)
        p.add_argument("--option", action="append", required=True, help='"A|label|wn-shot.jpg" (shot optional)')
        p.add_argument("--recommend")
        p.add_argument("--why")
        decision(p.parse_args(rest))
    elif cmd == "decision-answer":
        p = argparse.ArgumentParser(prog="whatsnew.py decision-answer")
        p.add_argument("id")
        g = p.add_mutually_exclusive_group(required=True)
        g.add_argument("--option")
        g.add_argument("--clear", action="store_true", help="un-pick: open again")
        p.add_argument("--words")
        p.add_argument("--source", default="chat", choices=["chat", "phone", "board"])
        decision_answer(p.parse_args(rest))
    elif cmd == "decision-revise":
        p = argparse.ArgumentParser(prog="whatsnew.py decision-revise")
        p.add_argument("id")
        p.add_argument("--question")
        p.add_argument("--option", action="append", help='"A|label|wn-shot.jpg" — replaces the whole list')
        p.add_argument("--recommend")
        p.add_argument("--why")
        decision_revise(p.parse_args(rest))
    elif cmd == "decision-withdraw":
        p = argparse.ArgumentParser(prog="whatsnew.py decision-withdraw")
        p.add_argument("id")
        p.add_argument("--why")
        decision_withdraw(p.parse_args(rest))
    elif cmd == "shot" and len(rest) == 2:
        shot(*rest)
    elif cmd == "check":
        check()
    elif cmd == "testflight" and len(rest) >= 2 and rest[0] == "--since":
        testflight(rest[1], rest[3] if len(rest) >= 4 and rest[2] == "--out" else None)
    elif cmd == "build":
        p = argparse.ArgumentParser(prog="whatsnew.py build")
        p.add_argument("--number", type=int, required=True)
        p.add_argument("--commit")
        p.add_argument("--time")
        a = p.parse_args(rest)
        build(a.number, a.commit, a.time)
    elif cmd == "areas-remap":
        areas_remap()
    elif cmd == "convert":
        convert()
    elif cmd == "resolve":
        print("resolve isn't needed any more: `add` stamps the time, and scripts look up commits when they need them")
    else:
        print(__doc__)
