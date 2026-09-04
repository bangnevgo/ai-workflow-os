# MEMORY INDEX — baca dulu di awal sesi (dipromosikan via dream)

Sumber: ledger + journal penolakan. Detail di file topik; yang di sini hanya sinyal yang harus dibawa dari sesi sebelumnya.

## Status sekarang
  - **marketing/promo-harbolnas** — SELESAI  (update 2026-09-04T19:45)
  - **operasional/checkout-redesign** — BERJALAN  (update 2026-09-04T19:45)
  - **website/checkout-redesign** — BERJALAN  (update 2026-09-04T19:45)
  - **website/launch-page** — SELESAI  (update 2026-09-04T19:45)

## Pelajaran (jangan ulangi)
  - [evidence] operasional: 2× klaim SELESAI tanpa bukti konkret — selalu bawa --evidence (url / screenshot / hasil test)…
  - [verification] operasional: 2× klaim SELESAI tanpa cara memeriksa — selalu bawa --verification (mis. curl -I -> 200 O…
  - [hold] website: 2× closing ditahan dependency terbuka — cek `workflow depend list` sebelum klaim SELESAI. Contoh: web…
  - [state] operasional: 1× transisi status tidak sah (mis. SELESAI langsung dari IDE) — wajib lewat SIAP-JALAN/BERJALAN.…
  - [owner] website: 1× mencoba operasi khusus owner (override/reopen/remove depend) — itu hak owner. Contoh: website/lau…

## Baca lanjut
  - 00-STATE.md: snapshot status seluruh divisi
  - 10-PROJECTS.md: konteks terkompilasi per proyek (evidence, depend, catatan)
  - 20-LESSONS.md: pola kesalahan dari journal penolakan
  - 30-DECISIONS.md: keputusan owner (override/reopen) + alasan
  - 40-CROSSLINKS.md: peta dependency lintas divisi
  - 50-AGENTS.md: pola aktivitas per platform