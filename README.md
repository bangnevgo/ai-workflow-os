<p align="center">
  <img src="https://img.shields.io/badge/python-3.9%2B-3776AB?style=for-the-badge&logo=python&logoColor=white" alt="python 3.9+"/>
  <img src="https://img.shields.io/badge/dependencies-zero%20%E2%80%94%20stdlib%20only-2ea44f?style=for-the-badge" alt="zero dependencies"/>
  <img src="https://img.shields.io/badge/ledger-append--only-critical?style=for-the-badge" alt="append-only ledger"/>
  <img src="https://img.shields.io/badge/state%20machine-5%20statuses-blueviolet?style=for-the-badge" alt="5-state machine"/>
  <img src="https://img.shields.io/badge/tests-37%20passing-success?style=for-the-badge" alt="37 tests passing"/>
  <img src="https://img.shields.io/badge/design-Memory%20%26%20Dreaming-8b5cf6?style=for-the-badge" alt="Memory & Dreaming design"/>
</p>

# 🤖 ai-workflow-os

## One append-only ledger. Six business divisions. Five AI platforms. **Zero ops team.**

> **TL;DR — keeping multiple AI agents in sync.** Running several LLM platforms (Claude,
> ChatGPT, Gemini, …) on the same work? This is a **single source of truth for AI agent
> teams**: an append-only, tamper-evident JSONL ledger where "done" is **evidence-gated**,
> closed projects are held by **open dependencies**, and cross-session memory is compiled
> from session logs using the **Memory & Dreaming / Karpathy wiki pattern** — so agents
> never overwrite each other's finished work.

You run Content, Marketing, Operations, Sales, Finance, and Website through **five different
LLM platforms** — no ops team, just you and a fleet of agents. The hardest part is never the
models. It's that every platform carries its *own* memory and its *own* interpretation of
what happened.

> Platform A says the page is live. Platform B, two days later, rebuilds that same page —
> it never knew the work was done. Platform C logs another division's work as its own,
> because it was only "helping".

**ai-workflow-os is the single source of truth they all have to agree on.** Agents may claim
anything in chat. Nothing enters the official record except through one validated CLI — and
"done" is only ever accepted with **evidence** and **verification** attached.

---

## 🎯 The shape of the fix

```
 EVERY PLATFORM                                   ONE TRUSTED SYSTEM
┌───────────┐   ┌───────────┐   ┌───────────┐    ┌──────────────────────┐
│ Claude    │   │ ChatGPT   │   │ Gemini    │    │   workflow (CLI)     │
│ platform A│   │ platform B│   │ platform C│───▶│   the ONLY writer    │
└───────────┘   └───────────┘   └───────────┘    └──────────┬───────────┘
                   ⋮ and more                                  │ validates
                                                            ┌──▼───────────┐
                                                            │  append-only │
                                                            │  ledger/div  │  → git
                                                            └──────────────┘
```

Rules live in the **validator**, not in prompts. Prompts are advice; the validator is a rule
that cannot be bargained with.

### ⚡ Core guarantees

| # | Guarantee | What happens in practice |
|---|-----------|--------------------------|
| 1 | **One write path** | No status ever enters a ledger except through `workflow submit`. |
| 2 | **Division = your folder** | Ownership comes from the *working directory*, never from what a model *claims* in chat. |
| 3 | **Validators reject, they don't warn** | Empty `--evidence` or `--verification` on `SELESAI` → **exit 2, zero bytes written**. |
| 4 | **Append-only, tamper-evident** | Each ledger line is chained to the previous one by SHA-256 (`seq`, `prev`) and tracked in git. |
| 5 | **Dependencies hold the door** | A project can't close while something it depends on is still open — unless *you* (owner) override it. |
| 6 | **Cross-session memory (`dream`)** | Session logs are consolidated out-of-band into a reviewed memory store every agent reads on startup. |

---

## 🛣️ State machine — five pure states, no "almost done"

```
  IDE            DISIAPKAN        SIAP-JALAN        BERJALAN         SELESAI
 (idea)         (prepared)       (ready)           (in progress)    (done)
   ───────────────▶ ───────────────▶ ───────────────▶ ───────────────▶
```

* `SELESAI` is the only transition under a hard lock: it must arrive from `SIAP-JALAN` or
  `BERJALAN`, **and** carry concrete `--evidence` + `--verification`.
* No "95% done". Nuance like *"done but needs a re-check"* is written as a free-form
  **note**, never as a fake state.
* Submitting the same state twice is a **no-op** — no duplicates, ever.
* Leaving `SELESAI` requires `workflow reopen`, and that's owner-only.

```bash
# from inside ~/nevgo/divisions/website/
$ workflow whoami
divisi   : website

$ workflow submit --project checkout-redesign --status SIAP-JALAN      # before starting
$ workflow submit --project checkout-redesign --status SELESAI \
      --evidence "url live: checkout.nevgo.id, screenshot attached" \
      --verification "curl -I checkout.nevgo.id -> 200 OK, checked manually"
```

Try to claim `SELESAI` without proof and the validator will refuse — then **record the
refusal as data** in `.workflow/rejections/`, so you can see which platform keeps making
unsubstantiated claims.

```
$ workflow submit --project pindah-server --status SELESAI --actor platform-d
✗ [verification] SELESAI requires --verification (how the claim was checked)
DITOLAK — no bytes written to the ledger.  (exit code 2)
```

---

## 💾 Memory & Dreaming — so sessions don't start from zero

Five platforms, cold starts, institutional amnesia — solved the way Anthropic's
*Memory & Dreaming* (the "Karpathy Wiki pattern") solves it. Your ledger is **episodic
memory**. A `dream` run is the out-of-band consolidation job that compiles it.

```
   sessions write                      compile out-of-band                 read on startup
┌──────────────────────┐   dream run   ┌──────────────────────────┐  promote   ┌──────────────┐
│ .workflow/ledger/    │ ────────────▶ │ proposal (never mutates  │ ─────────▶ │ .workflow/   │
│ .workflow/rejections │  4 phases     │ the input!)              │  (owner)   │ memory/      │
└──────────────────────┘               └──────────────────────────┘            └──────────────┘
```

Four phases: **Orient → Gather recent signal → Consolidate → Prune & Index**. The proposal
is a *candidate*, not a mutation — you review it, then promote or reject it.

```bash
$ workflow dream run                        # proposal: STATE, PROJECTS, LESSONS, DECISIONS, ...
$ workflow dream review latest
$ workflow dream promote latest --actor owner    # → live memory
$ workflow dream index                           # what agents read at session start
```

A promoted memory might tell your next agent: *"platform-a was rejected twice for closing
projects with open dependencies — check `workflow depend list` before claiming done"* or
*"owner already accepted launch-page with risk on 2026-09-04 — don't re-litigate it."*

> 📖 Full story: [`docs/DREAM.md`](docs/DREAM.md) · Design narrative (Indonesian):
> [`NEVGO_WORKFLOW_PRACTICAL.md`](NEVGO_WORKFLOW_PRACTICAL.md)

---

## 🚀 Quickstart

Zero external dependencies — Python ≥ 3.9 standard library + `git`.

```bash
git clone https://github.com/bangnevgo/ai-workflow-os.git ~/nevgo
cd ~/nevgo

./workflow init                      # config, 6 division folders, git repo (once)
cd divisions/website                 # ← division is decided by this folder
./workflow states                    # show the rules agents must follow
./workflow submit --project landing-v2 --status DISIAPKAN
./workflow board --write             # rebuild the BOARD.md summary from the ledgers
```

Replay a full multi-platform demo (scenario straight from the design document):

```bash
bash tools/seed_demo.sh              # 24 steps: rejects, holds, override, dream, ...
```

---

## 🗂️ Repository layout

```
~/nevgo/
├── workflow                # the CLI — the ONLY write path
├── config.json             # divisions, owner actors, policy (owner-editable)
├── BOARD.md                # derived view — always rebuildable from the ledgers
├── divisions/
│   ├── konten/  marketing/  operasional/
│   └── penjualan/  keuangan/  website/
├── .workflow/
│   ├── ledger/*.jsonl       # append-only, hash-chained source of truth
│   ├── rejections/*.jsonl   # validator refusals, stored as data
│   ├── dreams/              # proposals, live memory, dream journal
│   └── locks/               # inter-process write locks
├── docs/                    # agent contract, gap analysis, dream, deploy guide
├── tools/                   # demo seed + GitHub deploy helper
└── tests/                   # 37 automated checks (bash harness)
```

---

## ⌨️ Command cheatsheet

| Command | Purpose |
|---------|---------|
| `workflow init / whoami / states` | bootstrap · check your division from the folder · show the rules |
| `workflow submit` | **record a state transition** (the write path) |
| `workflow note` | free-form note — never touches state |
| `workflow status / log` | last state per project · raw append-only ledger |
| `workflow depend add/remove/list` | declare dependencies → **hold closing** until satisfied |
| `workflow reopen` | 🔒 owner: move `SELESAI` → `BERJALAN` (with a reason) |
| `workflow rejections` | read the validator's refusal journal |
| `workflow board --write` | rebuild the derived BOARD from the ledgers |
| `workflow dream run/list/review/promote/reject/index/journal` | Memory & Dreaming lifecycle (promote/reject = 🔒 owner) |
| `workflow verify` | check hash-chain + head-pointer integrity of every store |
| `workflow commit` | commit ledgers + BOARD to git |
| `workflow wipe` | 🔒 owner: start clean |

🔒 = owner-only. Owner actors live in `config.json` (`owner_actors`, default `["owner"]`);
agents identify themselves with `--actor <name>` or `NEVGO_ACTOR`.

**Exit codes for automation** — 0 = OK/no-op · 1 = system error · 2 = rejected by validator ·
3 = closing held by an open dependency.

---

## 🧠 Design decisions that make it trustworthy

- **Ledger = source of truth; BOARD = a view.** Crash the backend and you rebuild the BOARD
  from the ledgers. Corrupt a ledger and `git checkout` brings it back — history is versioned.
- **`cc` ≠ execute.** Cross-division help is *recorded* as `--cc DIV:project` but triggers
  nothing. Activation stays manual, with the owner.
- **One writer, always.** Hash-chained lines + per-division file locks mean five platforms can
  write *simultaneously* without lost or duplicated entries.
- **Prompt is advice; validator is law.** Rules are enforced in code paths, so their
  enforcement doesn't depend on how obedient a given model happens to be.
- **Division from the filesystem.** An agent spawned in `divisions/website/` *is* Website —
  the claim can't be forged in a chat message.

> Agent-facing contract to paste into any platform's system prompt:
> [`docs/RULES_FOR_AGENTS.md`](docs/RULES_FOR_AGENTS.md) · honest limits & gaps:
> [`docs/GAP-MANUAL.md`](docs/GAP-MANUAL.md)

---

## 🧭 Status & roadmap

- ✅ v0.1 prototype running with demo data, seed replay, and **37 passing tests**
- ✅ Multi-platform-safe writes (locks, dedupe no-ops, hash chains)
- ✅ Validator refusals recorded as data (closes a gap from the design doc)
- ✅ Memory & Dreaming (cross-session, review-gated)
- ◻️ Work-quality evaluation (not just "recorded correctly") — still the human's job
- ◻️ Scheduled `dream run` (e.g. nightly via cron), platform integration wrappers

---

## 📜 License

Internal/personal prototype — design narrative and implementation decisions are documented
in this repository for replication. See [NEVGO_WORKFLOW_PRACTICAL.md](NEVGO_WORKFLOW_PRACTICAL.md)
for the "how to copy this setup" playbook.

<p align="center"><sub>Made to stop trusting "it's done" — and start being able to check.</sub></p>
