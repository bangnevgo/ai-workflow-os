# LESSONS — pola kesalahan terbaru (dari journal penolakan)

_Fase Gather: hanya kejadian penolakan dalam jendela waktu terakhir_ (cutoff: 2026-08-28 19:45:49.198047+00:00).

- [evidence] operasional: 2× klaim SELESAI tanpa bukti konkret — selalu bawa --evidence (url / screenshot / hasil test). Contoh: operasional/pindah-server → SELESAI oleh platform-d.
- [verification] operasional: 2× klaim SELESAI tanpa cara memeriksa — selalu bawa --verification (mis. curl -I -> 200 OK). Contoh: operasional/pindah-server → SELESAI oleh platform-d.
- [hold] website: 2× closing ditahan dependency terbuka — cek `workflow depend list` sebelum klaim SELESAI. Contoh: website/checkout-redesign → SELESAI oleh platform-a.
- [state] operasional: 1× transisi status tidak sah (mis. SELESAI langsung dari IDE) — wajib lewat SIAP-JALAN/BERJALAN. Contoh: operasional/pindah-server → SELESAI oleh platform-d.
- [owner] website: 1× mencoba operasi khusus owner (override/reopen/remove depend) — itu hak owner. Contoh: website/launch-page → SELESAI oleh platform-d.

> Aturan-aturan ini hidup di validator (`workflow states`). Baris di atas hanya memberi tahu platform mana yang paling sering melanggarnya.
