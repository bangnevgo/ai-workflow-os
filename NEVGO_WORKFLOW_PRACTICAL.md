# Cara Saya Bikin 6 Divisi Bisnis Percaya Catatan yang Sama — Meski Dikerjakan 5 Platform AI Berbeda

saya jalankan enam divisi bisnis — Konten, Marketing, Operasional, Penjualan, Keuangan, Website — lewat lima platform LLM berbeda. tidak ada tim ops. cuma saya, dan agen-agen ini yang bekerja di masing-masing divisi.

saya tetap yang memutuskan kapan sesuatu benar-benar "selesai."
yang tidak lagi saya kerjakan: mengecek satu-satu apakah klaim "sudah selesai" dari tiap platform itu benar.

di bawah ini saya tunjukkan persis bagaimana saya mengatur ini:

- kenapa saya awalnya tidak percaya catatan platform manapun
- satu jalur tulis yang jadi jantung sistemnya
- state machine yang menolak, bukan cuma mengingatkan
- bagaimana saya kasih agen konteks lintas divisi tanpa kehilangan kontrol
- aturan yang bikin ini tidak berantakan
- cara meniru setup ini kalau kamu mau

## Yang Sudah Saya Punya

Tools-nya sudah lengkap. Lima platform LLM masing-masing sudah jago di bidangnya — satu bagus untuk konten, satu untuk kode, satu untuk riset.

Yang tidak ada: cara supaya semua platform itu **sepakat soal apa yang sudah benar-benar terjadi**.

Platform A bilang halaman sudah live. Platform B, dua hari kemudian, mengerjakan ulang halaman yang sama karena tidak tahu itu sudah dikerjakan. Platform C mencatat pekerjaan divisi lain sebagai miliknya sendiri karena "membantu" tanpa saya minta.

Masalahnya bukan model yang bodoh. Masalahnya setiap platform bawa memori dan interpretasinya sendiri, dan tidak ada satupun yang jadi sumber kebenaran bersama.

## Yang Saya Bangun

Versi singkatnya: agen boleh mengklaim apa saja di percakapan, tapi klaim itu **tidak bisa masuk catatan resmi** kecuali lewat satu jalur tulis yang divalidasi.

Satu CLI. Semua platform, semua divisi, wajib lewat situ untuk mencatat progres.

```
$ workflow submit --project "redesign-checkout" --status SIAP-JALAN
$ workflow submit --project "redesign-checkout" --status SELESAI \
    --evidence "url live: checkout.nevgo.id, screenshot terlampir" \
    --verification "curl -I checkout.nevgo.id → 200 OK, dicek manual"
```

*(ini bentuk ilustrasi — command asli saya beda, tapi prinsipnya sama: tidak ada status yang tercatat tanpa evidence dan verification.)*

Kalau evidence atau verification-nya kosong, command-nya ditolak. Bukan diperingatkan — ditolak. Tidak ada byte yang tertulis.

## State Machine-nya Cuma Lima

`IDE → DISIAPKAN → SIAP JALAN → BERJALAN → SELESAI`

Tidak ada status lain. Tidak ada "hampir selesai" atau "selesai tapi masih ada yang perlu dicek" — kondisi seperti itu ditulis sebagai catatan bebas, bukan status. Status tetap murni: di tahap mana pekerjaan ini sekarang.

Transisi ke SELESAI itu satu-satunya yang saya kunci ketat. Yang lain lebih longgar — tapi tetap harus lewat CLI yang sama, supaya semuanya tercatat di satu tempat.

## Divisi Mana Aktif? Filesystem yang Menentukan, Bukan Agen

Ini bagian yang paling saya sukai dari setup ini.

Kalau agen dipanggil dari folder `~/nevgo/website/`, dia otomatis dianggap kerja di divisi Website. Bukan karena dia bilang begitu di chat — karena working directory-nya memang di situ.

Efeknya: saya tidak perlu percaya platform mana pun soal "saya lagi kerja di divisi apa." Itu ditentukan dari luar model, jadi tidak peduli seberapa patuh platform itu terhadap instruksi saya.

Kalau ada kerjaan lintas divisi — agen Website perlu bantu Marketing — itu tercatat sebagai CC. CC ini tidak memicu eksekusi apa pun. Tetap saya yang aktivasi manual kalau memang perlu.

## Contoh Nyata: Divisi Website

Brief yang saya kasih ke agen di divisi ini kira-kira begini:

```
setiap kali kamu selesai satu task,
1. submit status SIAP-JALAN dulu sebelum mulai kerja
2. setelah selesai, submit SELESAI dengan evidence konkret
   — bukan "sudah saya buat", tapi url/screenshot/hasil test
3. kalau ada dependency ke proyek lain yang belum selesai,
   sistem otomatis nahan closing-nya sampai saya rekonsiliasi manual
```

Yang saya dapat balik bukan laporan chat yang harus saya percaya begitu saja. Saya dapat entry di ledger yang sudah punya evidence, dan kalau ternyata evidence-nya lemah, saya yang putuskan reject-nya — bukan model yang putuskan sendiri statusnya valid.

## Kenapa Saya Tidak Percaya "Laporan Selesai" Begitu Saja

Sebelum ada ini, kegagalan yang paling sering terjadi:

**Klaim tanpa bukti.** "Sudah selesai" berdasarkan test lokal atau file yang ada — bukan cek ke target sebenarnya.

**Antar platform tidak nyambung.** Platform yang beda-beda nyentuh hal yang sama, hasilnya saling bertentangan.

**Kepemilikan kabur.** Satu agen bantu domain lain, terus catat itu sebagai kerjaannya sendiri.

Saya coba perbaiki ini dengan nulis instruksi lebih detail di prompt. Tidak jalan lama — makin panjang instruksinya, makin sering dilanggar.

Yang jalan: pindahkan aturan itu dari prompt ke validator. Prompt itu nasihat. Validator itu aturan yang tidak bisa ditawar.

## Aturan yang Bikin Ini Tidak Berantakan

**Satu penulis per ledger.** Tiap divisi punya ledgernya sendiri, append-only, cuma bisa ditulis lewat CLI yang sama. Ringkasan gabungan (saya sebut BOARD) itu view turunan yang cuma backend yang tulis — jadi tidak pernah ada momen ledger dan ringkasannya beda.

**Tulis dua kali, hasilnya tetap satu.** Kalau agen kirim entry yang sama dua kali (kadang kelewat semangat), itu jadi no-op. Tidak ada duplikat.

**Dependency ditahan otomatis.** Kalau proyek A mau ditutup tapi proyek B masih nunggu hasilnya, sistem menahan closing-nya sampai saya yang rekonsiliasi — bukan diasumsikan beres oleh agen.

**Kalau backend rusak, ledger tetap sumber kebenaran.** BOARD itu cuma tampilan. Kalau backend crash, saya bisa build ulang BOARD dari ledger. Ledgernya sendiri teks biasa yang di-track git — kalau rusak, saya tinggal balik ke commit sebelumnya.

## Apa yang Masih Manual

Aktivasi kerja lintas divisi — tetap saya yang putuskan, tidak otomatis.
Evaluasi kualitas kerja (bukan cuma "tercatat dengan benar") — masih backlog.
Penolakan dari validator sekarang cuma muncul di terminal, belum saya catat sebagai data terpisah.

## Cara Meniru Setup Ini

Kalau kamu mau bikin versi kamu sendiri, saya sarankan urutannya begini:

**1. Mulai dari satu divisi/domain, bukan semua sekaligus.**
Pilih yang paling sering ada masalah "katanya sudah selesai tapi ternyata belum."

**2. Buat satu jalur tulis, bukan biarkan tiap platform nulis ke tempatnya sendiri.**
Bisa sesederhana satu script CLI yang wajib dipanggil sebelum status berubah.

**3. Wajibkan evidence sebelum status final, dan tolak kalau kosong.**
Jangan taruh ini sebagai instruksi di prompt — taruh sebagai pengecekan yang benar-benar menolak pemanggilan.

**4. Tentukan kepemilikan dari sesuatu di luar model.**
Working directory, nama folder, apa saja yang tidak bisa "diklaim" oleh model itu sendiri.

**5. Simpan histori sebagai append-only, bukan yang bisa ditimpa.**
Supaya kalau ada yang salah, kamu tetap bisa lacak apa yang sebenarnya terjadi.

**6. Baru tambah divisi berikutnya kalau yang pertama sudah stabil.**
Jangan hubungkan semuanya di hari pertama.

Saya tidak buru-buru bikin ini pintar. Saya cuma mau satu hal: kalau sesuatu tercatat "selesai" di sistem saya, saya tidak perlu ragu lagi apakah itu benar.
