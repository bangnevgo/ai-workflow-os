# nevgo-workflow

Satu jalur tulis untuk mencatat progres — dipakai 6 divisi bisnis (Konten,
Marketing, Operasional, Penjualan, Keuangan, Website) yang dikerjakan lewat
5+ platform LLM berbeda, tanpa tim ops.

Desain ini dijelaskan di `NEVGO_WORKFLOW_PRACTICAL.md`. Repo ini adalah
prototipe nyata dari desain itu. Baca dulu README ini, lalu `workflow states`
untuk aturannya.

## Prinsip inti

1. **Satu jalur tulis.** Tidak ada status yang masuk catatan resmi kecuali
   lewat CLI `workflow`. Ledger tiap divisi *append-only* (tidak bisa ditimpa),
   di-*track* git, dan dirantai hash — kalau ada yang mengubah sejarah, terdeteksi.
2. **Divisi ditentukan oleh working directory**, bukan oleh klaim model.
   Agen yang dipanggil di `~/nevgo/divisions/website/` = divisi Website.
   Tidak peduli apa yang model "bilang" di chat.
3. **Validator menolak, bukan mengingatkan.** Transisi ke `SELESAI` wajib
   membawa `--evidence` (bukti konkret) dan `--verification` (cara bukti itu
   diperiksa). Kosong = ditolak = *tidak ada byte yang tertulis*. Aturan ini
   hidup di kode, bukan di prompt.
4. **State machine murni:** `IDE → DISIAPKAN → SIAP-JALAN → BERJALAN → SELESAI`.
   Tidak ada "hampir selesai". Kondisi semacam itu ditulis sebagai catatan
   bebas (`workflow note`), bukan status.
5. **Ledger sumber kebenaran; BOARD cuma tampilan.** `BOARD.md` di-root adalah
   view turunan yang selalu dibangun ulang dari ledger (`workflow board --write`).
   Hapus pun tidak masalah.
6. **Closing ditahan dependency.** Kalau proyek A mau ditutup tapi proyek B
   masih menunggu hasilnya, sistem menahan (`exit code 3`) sampai owner
   merekonsiliasi — `--override` hanya bisa owner.

## Instalasi

Tidak ada dependency eksternal — stdlib Python (>=3.9) + git.

```bash
# symlink supaya perintah `workflow` tersedia di PATH:
bash install.sh            # memasang ke /usr/local/bin
# atau biarkan apa adanya dan panggil ./workflow dari dalam folder nevgo
```

Struktur setelah `workflow init`:

```
~/nevgo/
├── workflow                 ← CLI (satu jalur tulis)
├── config.json              ← divisi, state machine, policy (bisa diedit owner)
├── BOARD.md                 ← view turunan — JANGAN diedit manual
├── divisions/
│   ├── konten/  marketing/  operasional/
│   ├── penjualan/  keuangan/  website/
├── .workflow/
│   ├── ledger/*.jsonl        ← ledger append-only per divisi (sumber kebenaran)
│   ├── rejections/*.jsonl    ← journal penolakan validator (data terpisah)
│   └── locks/                ← kunci tulis (anti-race antar platform)
└── docs/  tools/  tests/
```

## Quickstart

```bash
workflow init                       # sekali saja; buat config + folder + git
cd divisions/website                # divisi = dari FOLDER ini

workflow whoami                     # → divisi: website

# status awal sebuah proyek
workflow submit --project redesign-checkout --status DISIAPKAN

# SIAP-JALAN sebelum mulai kerja (boleh tanpa evidence — status longgar)
workflow submit --project redesign-checkout --status SIAP-JALAN

# SELESAI: wajib evidence + verification, kalau tidak → DITOLAK (exit 2)
workflow submit --project redesign-checkout --status SELESAI \
    --evidence "url live: checkout.nevgo.id, screenshot terlampir" \
    --verification "curl -I checkout.nevgo.id -> 200 OK, dicek manual"

workflow status                      # lihat status tiap proyek
workflow board --write               # regenerasi BOARD.md (view turunan)
```

## Perintah

| Perintah | Fungsi |
|---|---|
| `workflow init` | buat struktur, `config.json`, folder divisi, repo git |
| `workflow whoami` | divisi apa yang ditentukan cwd (cek sebelum submit) |
| `workflow states` | tampilkan state machine + aturan |
| `workflow submit` | catat transisi status — **jalur tulis utama** |
| `workflow note` | catatan bebas (tidak mengubah status) |
| `workflow status [--division X] [--json]` | status terakhir semua proyek |
| `workflow log [--division X] [--project P]` | isi mentah ledger (append-only) |
| `workflow rejections` | journal penolakan validator |
| `workflow depend add/remove/list` | kelola dependency antar proyek/divisi |
| `workflow reopen` | *khusus owner*: buka lagi dari SELESAI → BERJALAN |
| `workflow board [--write]` | tampilkan / tulis `BOARD.md` |
| `workflow verify` | cek integritas hash-chain seluruh store |
| `workflow commit` | commit ledger + BOARD ke git |
| `workflow wipe` | *khusus owner*: mulai bersih (menghapus data) |

**Exit codes untuk otomasi:** `0` OK / no-op, `2` ditolak validator,
`3` ditahan dependency, `1` error sistem.

**Aktor** diisi lewat `--actor` atau env `NEVGO_ACTOR` (default `manual`).
Contoh: `NEVGO_ACTOR=claude-workflow-divisi ./workflow submit ...`.
Nama di `owner_actors` (default: `owner`) = satu-satunya yang boleh
`--override`, `reopen`, `depend remove`, `wipe`.

## Anti-duplikat & idempotensi

Submit status yang sama dua kali = *no-op* (tidak ada baris ditulis).
Ledger dirantai `seq` + hash `prev`, dengan kunci tulis antar-proses, jadi
dua platform yang menulis bersamaan tidak saling menabrak atau menduplikat.

## Meniru desain ini

Reproduksi dari `workflow` source: validasi di `validate_submit()`, tulis di
`append_entry()` (satu-satunya fungsi yang menyentuh store), tampilan di
`generate_board()`. Alur lengkap langkah-demi-langkah ada di
`NEVGO_WORKFLOW_PRACTICAL.md` (bagian "Cara Meniru Setup Ini").

## Roadmap / gap yang masih terbuka

| Di dokumen | Status di prototipe |
|---|---|
| Penolakan cuma muncul di terminal | ✔ sekarang tercatat di `.workflow/rejections/` |
| Aktivasi lintas divisi tetap manual | ✔ `--cc` dicatat, tidak mengeksekusi apa pun |
| Evaluasi kualitas kerja (bukan sekadar "tercatat benar") | ○ masih backlog |

Lihat `docs/GAP-MANUAL.md` untuk penjelasan tambahan, dan `docs/RULES_FOR_AGENTS.md`
untuk kontrak singkat yang bisa ditempel ke prompt/platform AI mana pun.
