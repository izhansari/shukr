---
name: close-out
description: Save the item you're on so the team stays smart — docs, rules to memory, parked ideas, commit + push, a lean What's new, Plan page, the record for whoever's next; then ask: archive · start a new task here · stay on the same task
---
**Why this exists (Izhan, 2026-10-17):** so nothing is lost and the organisation gets smarter. The readers are a fresh
agent session, the sessions working in parallel right now, and Izhan's planning — not Izhan reading records. What has been
lost before: things he said "later" to, how he wants us to work, and why a choice was made (what was tried and dropped).
He runs it (a) at the end of a fork / side session he'll archive, (b) as a save button in the main session before the next
item, (c) before clearing the chat for a new task. It never installs on the phones and never uploads to TestFlight.

Rules come from CLAUDE.md (Team, What's new); re-read those sections first. Your name (Frank / Sami / Bradley) starts every
commit; the board is `/Users/izhanansari/Coding and Tinkering/shukrGit/board/` (zsh); `whatsnew.py` is in the app repo's
`scripts/`. Work through these in order:

1. **Ready?** If anything is half-built or unchecked, say what and stop — never close out a guess. Note what you checked and
   what you couldn't (his phone, Siri, the watch…).
2. **Docs:** replace the feature's lines in `docs/features/<area>.md` (current behaviour only); CLAUDE.md only if a rule /
   trap / index line changed; `docs/app-store-features.md` if a user-facing feature changed; `docs/design-language.md` + a
   picture if he approved a new pattern.
3. **How he wants us to work → memory, with his OK.** Go through this conversation for every new rule or preference about
   *how to work* (not code facts — those live in git and docs). Drop any an existing memory file already covers (read
   MEMORY.md and the matching files). Then ask with **AskUserQuestion** before saving anything:
   - first question: "Save these N rules to memory?" — options **Save all** · **Skip all** · **Pick one by one**, each rule
     listed in a line in the question's text or the options' descriptions;
   - "Pick one by one": follow-up multi-select questions with up to 4 rules each as checkboxes (≤ 4 questions per call).
   Save only what he ticks (one file per rule, frontmatter, `**Why:**` + `**How to apply:**` with his words, a line in
   MEMORY.md; update an existing file rather than duplicating).
4. **Parked ideas:** go through the conversation for everything he said "later", "park", "keep in mind", "come back to",
   "push to the side" about. For each one not already on the Plan page (`idea.sh` / the board) or in a handoff's open list:
   `idea.sh dump "<his words, verbatim>" --from chat` → `idea.sh add <id> --dump <dump> --kind new --area <AREA> --title …
   --point …`. List them all in the write-up.
5. **Commit + push** (no install): `<Name>: <what changed>` + his words where they define it + "tried X, dropped because Y"
   (the *why* is the part that gets lost). `git pull --rebase origin claude/tasbeeh-zikr-updates`, then
   `git push origin HEAD:claude/tasbeeh-zikr-updates`. Never main, never force.
   **Shared checkout:** forks share this folder. Stage only your own files, by name. If others' uncommitted edits are in the
   tree, copy them aside, `pull --rebase --autostash`, and check each comes back byte for byte; never touch anyone's stash.
6. **What's new — lean** (only for something he'd see): first check `shukr/WhatsNew.jsonl` for an entry any session already
   wrote for the same item — if one covers it, skip. Otherwise one entry per thing he'd recognise: `whatsnew.py add --topic …
   --title "<how it works, 2–3 lines>" --headline "<≤ 40 chars>" --try "…" --ask <slug> --ask-words "<his words, verbatim>"
   --notes "<checked / not checked; Tried and dropped: …>" --checked sim|phone`. A screenshot only if one was already taken
   while testing (`whatsnew.py shot <png> <name>` → `--shot wn-<name>.jpg`) — never relaunch a sim just for the picture.
   An earlier entry for the same ask: add the new one, then `status --entry <old> --set replaced`. Commit + push it.
7. **Plan page:** if the item isn't there: `idea.sh dump "<his words>" --from chat` → `idea.sh add …`. Then
   `queue.sh add <id> <name> --title …` (if missing), `queue.sh start <id> --force`, `queue.sh done <id> <hash>`,
   `idea.sh link <id> --queue <id> --commit <hash>`.
8. **The record for whoever's next:**
   - **A fork / side session** (`mcp__ccd_session_mgmt__get_session` with "self" → `parentSessionId`): send the parent
     (SendMessage) a short note — the hashes, what's done, what's open, any trap — and add one line with the same to the
     parent's `board/handoff-<name>.md` (it survives the parent compacting). No handoff file of its own.
   - **The main session:** refresh your own `board/handoff-<name>.md` (≤ 20 lines: now, next, half-done, open, traps).
9. **Tidy:** delete only the sims, scratch files and branches you made; never another engineer's.
10. **Write-up** (his rule: a full one, plain): what changed, the hashes, what's on the team line, what wasn't checked, what
    was saved to memory, the parked ideas swept, anything left for him to decide — and a **to-check list**: each gesture,
    what to do, what should happen.
11. **Then ask "What now?"** with **AskUserQuestion**, exactly these three options (his words, 2026-10-17):
    - **Archive** (the pick for a fork / side session): archive yourself (`mcp__ccd_session_mgmt__get_session` "self" for
      the id → `mcp__ccd_session_mgmt__archive_session`; load them with ToolSearch if deferred).
    - **Start a new task here** (the pick for the main session used as a save button): make sure the handoff is current
      (step 8; a fork writes `board/handoff-<name>-<fork>.md`, ≤ 20 lines: what's open, what was decided, traps), say in one
      line "Clearing now — type the new task when the chat is empty; I'll re-read CLAUDE.md and <handoff file> first",
      then `mcp__ccd_session_mgmt__clear_session` "self" (he approves). The new context starts from CLAUDE.md + the handoff.
    - **Stay on the same task here**: nothing more; wait for him.
    **The close-out ends here. It never starts, plans or interviews the next task** — not even when he describes one in
    Other: put his words verbatim as one line in the handoff ("Next, his words: …"), confirm in one line, and stop. (It
    went off on a long interview inside the close-out once; he meant "clear the context, then the new task".)
