# BOARD NEVGO — ringkasan gabungan seluruh divisi

> View turunan. Dibangun otomatis dari ledger oleh `workflow board --write` pada 2026-09-04T19:46:01+00:00.
> Jangan diedit manual — akan tertimpa. Ledger di `.workflow/ledger/` adalah sumber kebenaran.

**State machine:** IDE → DISIAPKAN → SIAP-JALAN → BERJALAN → SELESAI  

_(status murni = tahap pekerjaan. Kondisi seperti 'selesai tapi perlu dicek lagi' ditulis sebagai catatan bebas lewat `workflow note`, bukan status.)_

## Ringkasan status

  IDE: 0 · DISIAPKAN: 0 · SIAP-JALAN: 0 · BERJALAN: 2 · SELESAI: 2

## Divisi Marketing (`marketing`)

   status  | proyek          | update | evidence terakhir                              | cc                       
  ---------+-----------------+--------+------------------------------------------------+--------------------------
   SELESAI | promo-harbolnas | 19:45  | landing promo live di /promo-harbolnas, hasil… | cc:konten:katalog-produk 


## Divisi Operasional (`operasional`)

   status   | proyek            | update | evidence terakhir | cc 
  ----------+-------------------+--------+-------------------+----
   BERJALAN | checkout-redesign | 19:45  | —                 |    


## Divisi Website (`website`)

   status   | proyek            | update | evidence terakhir                              | cc 
  ----------+-------------------+--------+------------------------------------------------+----
   BERJALAN | checkout-redesign | 19:45  | url live: checkout.nevgo.id, screenshot terla… |    
   SELESAI  | launch-page       | 19:45  | —                                              |    

## Dependency terbuka (closing ditahan sampai selesai/direkonsiliasi)

   dependen                  | ditunggu                    | status      | alasan                                   
  ---------------------------+-----------------------------+-------------+------------------------------------------
   website/checkout-redesign | → marketing/promo-harbolnas | ✓ terpenuhi | halaman checkout menampilkan copy & CTA… 
   website/launch-page       | → website/checkout-redesign | ✗ menunggu  | CTA launch-page membawa user ke checkout 

## Aktivitas terakhir

   proyek                        | kind     | transisi            | jam   | aktor      
  -------------------------------+----------+---------------------+-------+------------
   marketing/promo-harbolnas     | submit   | SIAP-JALAN→BERJALAN | 19:45 | platform-c 
   marketing/promo-harbolnas     | submit   | BERJALAN→SELESAI    | 19:45 | platform-c 
   operasional/checkout-redesign | submit   | IDE→BERJALAN        | 19:45 | platform-e 
   website/checkout-redesign     | submit   | SIAP-JALAN→SELESAI  | 19:45 | platform-a 
   website/checkout-redesign     | reopen   | SELESAI→BERJALAN    | 19:45 | owner      
   website/launch-page           | submit   | IDE→SIAP-JALAN      | 19:45 | platform-a 
   website/launch-page           | override | SIAP-JALAN→SELESAI  | 19:45 | owner      
   marketing/promo-harbolnas     | submit   | IDE→SIAP-JALAN      | 19:45 | platform-c 
   website/checkout-redesign     | submit   | IDE→SIAP-JALAN      | 19:45 | platform-a 

## Catatan bebas terbaru (bukan status)

- **website/launch-page** (owner, 2026-09-04T19:45): perlu dicek lagi banner promo setelah harbolnas turun minggu depan (catatan, bukan status)

## Penolakan validator terbaru

- **operasional/pindah-server** → SELESAI oleh platform-d (reject): ke SELESAI dari 'IDE' tidak diizinkan; harus lewat SIAP-JALAN / BERJALAN dulu
- **website/checkout-redesign** → SELESAI oleh platform-a (hold): closing ditahan otomatis sampai direkonsiliasi — masih ada proyek yang belum selesai terkait lewat …
- **website/launch-page** → SELESAI oleh platform-d (override-denied): operasi ini khusus owner (aktor 'platform-d' tidak ada di owner_actors=['owner'])
- **website/launch-page** → SELESAI oleh platform-a (hold): closing ditahan otomatis sampai direkonsiliasi — masih ada proyek yang belum selesai terkait lewat …
## Memori terkompilasi (Dreaming)

> Dipromosikan dari proposal `workflow dream` — baca sebelum mulai sesi baru: `workflow dream index`.

# MEMORY INDEX — baca dulu di awal sesi (dipromosikan via dream)
Sumber: ledger + journal penolakan. Detail di file topik; yang di sini hanya sinyal yang harus dibawa dari sesi sebel…
## Status sekarang
- **marketing/promo-harbolnas** — SELESAI (update 2026-09-04T19:45)


---
_Dibuat 2026-09-04T19:46:01+00:00. Sumber: `.workflow/ledger/*.jsonl`. Periksa integritas: `workflow verify`._