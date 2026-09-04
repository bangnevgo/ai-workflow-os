# Share Pack — cara "menjemput" pengunjung (dan star)

Repo sudah SEO-friendly (description, 17 topics, README panjang, indeks cepat oleh
Google & AI search). Yang belum ada: **distribusi**. File ini berisi teks siap-tempel
untuk beberapa kanal. Pilih satu atau dua, jangan semua sekaligus — masing-masing kanal
punya kultur sendiri, dan spam lintas kanal terlihat tidak tulus.

Repo: https://github.com/bangnevgo/ai-workflow-os

---

## 1) Hacker News — "Show HN" (potensi terbesar, English)

**Kenapa kanal ini:** audiens persis (engineer AI/agents), dan satu post Show HN yang
"nyangkut" bisa membawa ratusan pengunjung. Kultur HN: **jujur, teknis, sadar
keterbatasan**. Jangan jualan; tunjukkan masalah + trade-off. Posting jam 07:00–09:00
WIB tidak ideal — targetkan malam (sekitar 23:00–01:00 WIB) agar pagi waktu US Timur.

**Title (maks ~80 karakter, harus memancing):**
```
Show HN: I run 6 business divisions on 5 different AI platforms with no ops team
```

**Body — tempel apa adanya:**

> I manage Content, Marketing, Ops, Sales, Finance and Website using agents from five
> different LLM platforms (Claude, ChatGPT, Gemini, …), with no ops team. Model quality
> was never the problem. The problem: Platform A marks something "done", Platform B redoes
> it two days later because it never knew, Platform C logs another team's work as its own.
>
> So I built a single CLI that is the ONLY writer to per-division, append-only ledgers:
>
> - 5-state machine (IDE → DISIAPKAN → SIAP-JALAN → BERJALAN → SELESAI). Entering SELESAI
>   requires `--evidence` + `--verification` or the write is rejected (exit 2) — and the
>   rejection is itself recorded as data, so I can see which platform keeps claiming
>   "done" without proof.
> - Division ownership comes from the working directory the agent is spawned in, never
>   from what it claims in chat.
> - A project is HELD from closing while something it depends on isn't done; only I can
>   override, with a logged reason.
> - Ledgers are SHA-256 hash-chained and git-tracked: tampering is detectable, crashes
>   are recoverable.
> - `workflow dream` implements the Memory & Dreaming / Karpathy-wiki idea: it compiles
>   recent session logs + rejection history into a memory store (proposal, doesn't mutate
>   input), I review & promote it, and agents read it at session start — so they stop
>   repeating past mistakes.
>
> The principle that actually moved the needle: **put the rules in the validator, not in
> the prompt.** Prompts are advice; validators are law. Long prompts get ignored; a reject
> with exit code 2 and a recorded refusal doesn't.
>
> Zero dependencies (stdlib Python), 37 passing tests, `bash tools/seed_demo.sh` replays
> the full multi-platform story. Docs include an English contract to paste into any
> agent's system prompt.
>
> What will break when I scale this to more teams/agents? Feedback very welcome.

---

## 2) Reddit r/AI_Agents (English)

**Kultur:** suka contoh nyata + konteks, benci murni promosi. Pilih r/AI_Agents (paling
cocok) atau r/LocalLLaMA (kalau lebih teknis-model). Judul boleh bernada bertanya.

**Title:**
```
How I stopped 5 different AI platforms from overwriting each other's work (append-only ledger, no ops team)
```

**Body:**
> Running 6 business divisions with agents on 5 different LLM platforms. Big failure mode
> wasn't model quality — it was that each platform has its own memory, so "done" meant
> different things to each of them. Platform B kept redoing finished work; platform C
> claimed work that wasn't its own.
>
> Fix I'm using (repo + writeup): one CLI as the only write path to append-only ledgers,
> division determined by working directory, "done" gated on evidence+verification with
> refusals recorded as data, hash-chained lines so history is verifiable, and a
> review-gated "dream" step that consolidates session logs into memory agents read on
> startup.
>
> The thing that made rules stick: validator over prompt. Prompt = advice they ignore,
> validator = rejection with exit 2.
>
> Repo: https://github.com/bangnevgo/ai-workflow-os — happy to hear where this approach
> breaks down at larger scale.

---

## 3) X/Twitter thread (English)

**Kultur:** personal, satu "hook", jangan lebih dari ~7 tweet. Posting jam 19:00–21:00
WIB (pagi US).

**Tweet 1 (hook):**
> I run 6 business divisions using 5 different AI platforms. No ops team. The model
> quality was never the problem — it was that every platform had its OWN memory of what
> "done" means. 🧵

**Tweet 2:**
> Platform A said the page was live. Platform B rebuilt it 2 days later — never knew.
> Platform C logged another team's work as its own, "just helping". Total chaos, not
> because the models are dumb, but because there was no shared source of truth.

**Tweet 3:**
> Fix: agents may claim anything in chat. Nothing enters the official record except
> through ONE validated CLI. Append-only ledgers, one per division, git-tracked and
> hash-chained.

**Tweet 4:**
> The part I like most: division ownership comes from the FOLDER an agent runs in, not
> from what it says. A model can't "claim" it's working on Website if its cwd is
> divisions/marketing. Identity decided outside the model.

**Tweet 5:**
> "Done" = evidence + verification, or rejected. Empty claims get exit code 2 and the
> REFUSAL is recorded as data. Rules live in the validator, not the prompt — prompts are
> advice, validators are law. That one change fixed more than 10 rewrites of my system
> prompt ever did.

**Tweet 6:**
> Cross-session memory = a "dream" step (Memory & Dreaming / Karpathy wiki pattern):
> compile session logs + rejection history into a proposal, I review & promote it, agents
> read it at startup. They stop repeating mistakes instead of discovering them fresh each
> session.

**Tweet 7:**
> Zero deps, stdlib Python, 37 tests, demo replay included. Open-sourced the whole thing
> + the playbook so you can copy the setup:
> https://github.com/bangnevgo/ai-workflow-os

---

## 4) LinkedIn — versi Indonesia (personal branding)

**Kultur:** cerita + pelajaran, bahasa Indonesia halus, jangan terlalu jualan. Waktu
terbaik: Selasa–Kamis pagi.

**Draft:**

> Selama ini saya menjalankan enam divisi bisnis (konten, marketing, ops, sales,
> keuangan, website) dengan agen AI dari lima platform LLM berbeda — tanpa tim ops.
>
> Pelajaran terbesar yang saya dapat bukan soal modelnya, tapi soal memori. Setiap
> platform bawa ingatannya sendiri. Platform A bilang "sudah live", Platform B dua hari
> kemudian mengerjakan ulang karena tidak tahu, Platform C mencatat kerja divisi lain
> sebagai kerjanya sendiri karena "cuma bantu".
>
> Solusi yang akhirnya jalan bukan prompt yang lebih panjang — tapi memindahkan aturan
> dari prompt ke validator:
>
> • Satu CLI sebagai satu-satunya jalur tulis ke ledger append-only per divisi.
> • "Selesai" wajib bawa bukti (evidence) + cara verifikasi. Kosong? Ditolak, exit code 2,
>   dan penolakannya ikut tercatat sebagai data.
> • Divisi ditentukan dari folder tempat agen bekerja, bukan dari klaim di chat.
> • Proyek tidak bisa ditutup kalau masih ada dependency yang belum selesai.
> • Ledger dirantai hash & di-track git — kalau ada yang mengubah sejarah, ketahuan.
> • Terakhir, mekanisme "dream" (pola Memory & Dreaming / Karpathy wiki): pengalaman sesi
>   dikonsolidasi jadi memori yang dibaca semua agen saat mulai kerja — supaya kesalahan
>   tidak diulang dari nol.
>
> Prinsip yang paling mengubah segalanya: **prompt itu nasihat, validator itu hukum.**
> Instruksi sepanjang apa pun bisa dilanggar; penolakan dengan exit code tidak bisa
> ditawar.
>
> Sudah saya buka source-nya beserta panduan meniru setup-nya:
> https://github.com/bangnevgo/ai-workflow-os
> Masukan soal di mana pendekatan ini bakal jebol kalau di-scale sangat saya hargai.

---

## 5) Long-form (opsional, backlink terkuat)

Tulis artikel Medium/Substack/blog + link repo (backlink ke github.com). Judul yang
terbukti bekerja untuk format ini:

> **"I run 6 divisions on 5 AI platforms with no ops team. Here's the one ledger that keeps them honest."**

Kerangka artikel = dokumen desain Anda (`NEVGO_WORKFLOW_PRACTICAL.md`) ditambah bagian
"yang saya pelajari" + kode. Terjemahkan ke Inggris kalau target global.

---

## Checklist setelah posting

- [ ] Pantau komentar 1–2 jam pertama (HN/Reddit) dan balas dengan sopan — engagement awal menentukan naik-turun post.
- [ ] Jawab kritik dengan jujur; jangan defensif. Kritik "di mana ini jebol?" justru bagus untuk diskusi.
- [ ] Jangan posting semua kanal di hari yang sama — beri jeda 2–3 hari agar tiap kanal dapat perhatian penuh.
- [ ] Setelah ada 1–2 star dari luar, jangan dijadikan target; target sehat bulan pertama: 10–50 star.

## Ekspektasi jujur

Satu post "nyangkut" bisa membawa ratusan klik dan puluhan star. Tapi sebagian besar
post tidak nyangkut — itu normal. Yang Anda butuhkan adalah **beberapa percobaan
konsisten**, bukan satu tembakan ajaib. Setiap post yang tidak nyangkut tetap meninggalkan
backlink yang membantu SEO jangka panjang.
