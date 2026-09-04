# PROJECTS — konteks terkompilasi per proyek

_Dibuat 2026-09-04T19:45:49+00:00. Evidence/verification diambil dari entry terakhir yang menyediakannya._

## Marketing (`marketing`)
- **promo-harbolnas** — SELESAI
    evidence: landing promo live di /promo-harbolnas, hasil uji A/B lampiran
    verifikasi: curl -I nevgo.id/promo-harbolnas -> 200; dicek dua browser

## Operasional (`operasional`)
- **checkout-redesign** — BERJALAN

## Website (`website`)
- **checkout-redesign** — BERJALAN menunggu: marketing/promo-harbolnas(SELESAI)
    evidence: url live: checkout.nevgo.id, screenshot terlampir
    verifikasi: curl -I checkout.nevgo.id -> 200 OK, dicek manual
- **launch-page** — SELESAI menunggu: website/checkout-redesign(BERJALAN)
    evidence: url live: nevgo.id/launch, diuji di 3 browser
    verifikasi: curl -I nevgo.id/launch -> 200; cek klik CTA manual
    catatan (owner): perlu dicek lagi banner promo setelah harbolnas turun minggu depan (catatan, bukan status)
