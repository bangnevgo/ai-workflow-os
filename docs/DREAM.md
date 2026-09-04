# Dream — memori lintas sesi untuk multi-platform AI

Fitur `/dream` pada sistem ini adalah implementasi dari pola *Memory and
Dreaming* / Karpathy wiki (lihat artikel Dotzlaw *"Memory and Dreaming: How
Anthropic Just Shipped the Karpathy Wiki Pattern"*). Ini menjawab masalah
paling mendasar di `NEVGO_WORKFLOW_PRACTICAL.md`: setiap platform LLM bawa
memori dan interpretasinya sendiri — jadi "kesepakatan tentang apa yang sudah
terjadi" harus hidup di *luar* percakapan, dan **terus dikonsolidasi**.

## Peta konsep

| Lapisan memori | Di sistem ini |
|---|---|
| **Episodik** (rekaman sesi) | Ledger per divisi (`.workflow/ledger/*.jsonl`) + journal penolakan (`.workflow/rejections/*.jsonl`) — append-only |
| **Dreaming** (proses konsolidasi, *compile-time*) | `workflow dream run` — job out-of-band, 4 fase |
| **Semantik** (pengetahuan terkompilasi, *query-time*) | `.workflow/dreams/memory/` (INDEX + file topik) — dibaca agen di awal sesi |

Lingkarannya tertutup: *sesi menulis ledger → dreaming mengkonsolidasi →
memori dibaca sesi berikutnya*. Perbedaan dari eksekusi biasa: **tidak
sinkron** (tidak ada sesi yang menunggu) dan **tidak in-place** (input tidak
pernah diubah) — ini *proposal* yang menunggu gerbang manusia.

## Empat fase `dream run`

1. **Orient** — `00-STATE.md`: snapshot status seluruh divisi saat ini.
2. **Gather Recent Signal** — ambil hanya sinyal jendela waktu terakhir
   (default 7 hari, `--since-hours 0` = semua): event ledger + penolakan.
   Bukan dump mentah: langsung ke pola.
3. **Consolidate** — hasil jadi dokumen topik:
   - `10-PROJECTS.md` — per proyek: status, evidence/verification terakhir,
     dependency terbuka, catatan bebas terbaru.
   - `20-LESSONS.md` — taksonomi kesalahan dari penolakan validator
     (`evidence`, `verification`, `state`, `owner`, `hold`, …) + siapa yang
     paling sering melanggarnya. Merekam "apa yang salah kemarin" supaya
     sesi berikutnya tidak mengulang — mekanisme yang sama dengan angka
     "critical errors −97%" dari kasus Rakuten di artikel.
   - `30-DECISIONS.md` — keputusan owner (`override`/`reopen`) + alasan.
     Ini mencegah platform B dua hari kemudian "mengerjakan ulang" proyek
     yang sudah diputuskan owner.
   - `40-CROSSLINKS.md` — peta dependency lintas divisi (yang benar-benar
     terbuka sekarang), bukan klaim.
   - `50-AGENTS.md` — pola aktivitas tiap platform: siapa mencatat apa,
     siapa sering ditolak. Bahan mengarahkan brief berikutnya.
4. **Prune & Index** — `INDEX.md` dibatasi (cap `memory_index_max_lines`,
   default 200 baris, bisa diatur di `config.json`) supaya terbaca sekali
   pandang: status terkini + pelajaran teratas + pointer ke file topik.
   Konversi waktu relatif → absolut, buang yang bertentangan.

## Gerbang manusia

```bash
workflow dream run                          # proposal — tidak mengubah apa pun
workflow dream list                         # lihat status proposal
workflow dream review <id>                  # ringkas isi
workflow dream promote <id> --actor owner   # setelah Anda nilai layak
workflow dream reject <id> --actor owner --reason "kurang ini itu"
```

- `promote` memindahkan proposal ke memori aktif secara atomik
  (temp dir → rename, versi lama disimpan git). Ledger tidak pernah berubah.
- `reject` menulis `DECISION.md` di folder proposal + catatan di journal.
- Semua aktivitas dream tercatat append-only di `.workflow/dreams/journal.jsonl`
  (ikut `workflow verify`, di-track git).

## Kenapa ini penting di setup "6 divisi × 5 platform"

Tanpa lapisan semantik, tiap sesi mulai dingin: Platform A tidak tahu
Platform C dua hari lalu sudah membuktikan `SELESAI` (atau malah ditolak
validator). Memori aktif (`workflow dream index`) adalah *satu tempat yang
bisa dibaca semua platform di awal sesi* — konsisten karena dibangun dari
ledger yang sama, dan aman karena sudah direview owner. Validator tetap
penegak aturan; dream menambahkan **ingatan atas aturan yang pernah
dilanggar**, sehingga pelanggaran berhenti terulang.

## Kejujuran & batas

- Dream tidak menilai *kualitas* kerja — sama seperti backlog evaluasi
  kualitas di dokumen utama. Ia mengkonsolidasi fakta yang tercatat
  (status, evidence, penolakan, keputusan).
- Ringkasan hanya sebagus ledger sumbernya. Ledger yang jujur → memori
  berguna; ledger berisi klaim palsu → "organized noise". Struktur dasar
  tetap yang terpenting.
- Proses ini tidak memblokir sesi mana pun dan tidak menulis ke ledger;
  satu-satunya tulisannya adalah ke store proposal/memori + journal dream.
