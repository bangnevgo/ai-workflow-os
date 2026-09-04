# Gap manual → prototipe, dan catatan desain

Ringkasan dari `NEVGO_WORKFLOW_PRACTICAL.md`, dipetakan ke implementasi di repo ini.

## Yang di dokumen dibilang "masih manual" — status di prototipe

**1. "Penolakan dari validator sekarang cuma muncul di terminal, belum saya catat sebagai data terpisah."**
→ Sudah terisi di prototipe. Setiap penolakan (dan penahanan dependency) dicatat
ke `.workflow/rejections/<divisi>.jsonl` — append-only, hash-chain sama seperti
ledger. Baca dengan `workflow rejections`; tampil juga di BOARD.

**2. "Aktivasi kerja lintas divisi — tetap saya yang putuskan, tidak otomatis."**
→ Dipertahankan dengan sengaja. `--cc DIV[:PROYEK]` hanya mencatat bahwa bantuan
terjadi / diminta, tidak memicu eksekusi. Yang benar-benar mengubah jalannya
pekerjaan adalah `workflow depend add` (dependency ditahan sampai selesai) —
itu pun hanya menahan *closing*, bukan mengeksekusi task.

**3. "Evaluasi kualitas kerja (bukan cuma 'tercatat dengan benar') — masih backlog."**
→ Tetap backlog. Prototipe berhenti di "klaim harus terbukti & tercatat benar".
Menilai *kualitas* hasil (apakah UX-nya bagus, apakah tulisan marketing-nya
persuasif) memang tidak bisa otomatis — itu tetap pekerjaan owner. Ledger
menyediakan bahan untuk evaluasi itu: evidence tiap `SELESAI` adalah tempat
owner menilai.

## Pilihan desain yang perlu diketahui pemakai

| Keputusan | Alasan |
|---|---|
| Ledger dirantai hash (`seq`, `prev=sha256(baris sebelumnya)`) + head pointer | Append manual tanpa CLI bisa dideteksi; crash tidak membuat ledger "setengah jadi" tanpa jejak. |
| `verify` auto-heal head yang tertinggal satu baris | Crash antara *append baris* dan *tulis head* menghasilkan head basi; baris tetap valid, jadi di-*recover* — ledger tidak dianggap korup. |
| Submit status yang sama = no-op | Menjawab "tulis dua kali, hasilnya tetap satu" dari dokumen. |
| Backward di antara status aktif (mis. BERJALAN → SIAP-JALAN) dibiarkan longgar | Sesuai dokumen: "yang lain lebih longgar — tapi tetap harus lewat CLI yang sama". |
| Keluar dari SELESAI harus `reopen` + owner | SELESAI adalah titik yang paling sering di-*claim* palsu, jadi satu-satunya gerbang dua arah yang dijaga ketat. |
| Divisi dibaca dari *deepest match* sub-folder | Kalau nanti ada sub-divisi di dalam folder divisi, sistem memilih yang paling spesifik. |
| `depend` dicatat dua arah lewat incident edge | Menutup A yang ditunggu B juga menahan A — tidak hanya arah keluar. `dep_hold_policy: any` bisa diganti `outgoing`. |
| Semua tulis lewat temp-file + `os.replace`, fsync, kunci antar-proses | Aman dipakai beberapa platform AI *bersamaan* pada repo yang sama. |

## Ancamam model & batas kejujuran (jangan dibohongi)

Prototipe ini menegakkan aturan untuk agen yang *kooperatif tapi asal-asalan*:
agen yang mengklaim tanpa bukti akan ditolak dan penolakannya tercatat. Ini
tidak melindungi dari agen yang **sengaja jahat** (punya akses shell penuh,
bisa edit file apa pun). Yang melindungi dari itu adalah: repo git (jejak
setiap perubahan), pembatasan owner, dan praktik "CLI ini satu-satunya cara
yang dibolehkan" di `RULES_FOR_AGENTS.md`.

Kalau suatu hari perlu lebih kuat, arah yang masuk akal: `gpg` sign tiap baris,
dan/atau jalankan `workflow` lewat wrapper SSH di mesin terpisah sehingga
platform AI hanya mendapat *interface* perintah, bukan shell penuh.
