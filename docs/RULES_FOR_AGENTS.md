# Kontrak untuk Agen/Platform AI — tempel bagian ini ke prompt sistem

> Tujuan kontrak ini: semua platform AI memakai memori yang sama. Satu-satunya
> sumber kebenaran soal "sudah selesai atau belum" adalah ledger di
> `~/nevgo/.workflow/ledger/` — dan satu-satunya cara menulis ke sana adalah CLI
> `workflow`. Prompt ini hanyalah *nasihat*; yang menegakkan aturan adalah
> validator di CLI itu sendiri.

## Aturan yang tidak bisa ditawar

1. **Selesai itu harus dibuktikan, bukan diucapkan.** Jangan pernah menulis
   "sudah saya kerjakan" sebagai pengganti bukti. Bukti yang diterima: URL yang
   bisa di-*curl*, screenshot/artefak file, hasil test, output command.
2. **Satu-satunya jalur tulis adalah `workflow submit`.** Kalau kamu mencoba
   mencatat progres selain lewat CLI (misalnya menulis file di
   `.workflow/ledger/`), kamu tidak sedang membantu — kamu sedang merusak
   sumber kebenaran bersama.
3. **Jangan menebak divisi.** Divisi kamu ditentukan oleh *working directory*
   tempat kamu dipanggil. Cek dengan `workflow whoami`. Tidak ada argumen
   divisi pada `submit` — sistem membacanya dari folder.
4. **Status murni, 5 tahap saja:**
   `IDE → DISIAPKAN → SIAP-JALAN → BERJALAN → SELESAI`.
   Jangan mengarang status seperti "95%". Kalau ada kondisi tambahan, tulis
   lewat `workflow note`, bukan status.
5. **`SELESAI` hanya boleh setelah `SIAP-JALAN` atau `BERJALAN`**, dan WAJIB
   membawa `--evidence` + `--verification`. Kalau validator menolak, itu
   keputusan final — perbaiki klaim kamu, jangan coba akali.
6. **Jangan menutup proyek yang masih menunggu proyek lain.** Cek dulu
   `workflow depend list`. Kalau closing ditahan (`exit code 3`), itu sengaja:
   menunggu rekonsiliasi owner.
7. **Kerja lintas divisi dicatat sebagai `--cc`, dan itu tidak memicu eksekusi
   apa pun.** Jangan menganggap `cc` sebagai perintah untuk mengerjakan sesuatu
   di divisi lain. Kalau kamu di-`cc`, kamu mencatat; eksekusi tetap diputuskan
   owner.

## Urutan kerja per task

```text
1.  workflow whoami                     → pastikan divisi benar
2.  workflow status                     → pastikan belum dikerjakan orang lain
3.  workflow submit --project <slug> --status SIAP-JALAN     ← sebelum mulai kerja
4.  ... kerjakan ...
5.  Uji ke target sebenarnya, jangan cuma "test lokal"
    contoh:  curl -I https://... ; jalankan test suite; cek file yang live
6.  workflow submit --project <slug> --status SELESAI \
        --evidence "<bukti konkret: url/screenshot/hasil test/file>" \
        --verification "<cara bukti diperiksa>"
```

Kalau sebuah transisi ditolak, *selalu* cek `workflow rejections` supaya kamu
tahu kenapa — lalu kirim ulang dengan klaim yang benar.

## Identitas

Selalu isi `--actor` atau set env `NEVGO_ACTOR` ke nama kamu (mis.
`platform-a-konten`). Ledger harus bisa menjawab "siapa yang mencatat apa dan
kapan" — itu yang membuat antarsesama platform tidak saling menimpa.

## Larangan

- ❌ Menulis/append langsung ke `.workflow/ledger/*.jsonl` atau `BOARD.md`.
- ❌ Menghapus atau mengubah file ledger (append-only).
- ❌ Mengklaim SELESAI tanpa evidence + verification terhadap target nyata.
- ❌ Menggunakan `--override` / `workflow reopen` (khusus owner).
- ❌ Mencatat pekerjaan divisi lain sebagai status divisi kamu sendiri.
- ❌ Membuat status baru di luar 5 tahap yang ada.
