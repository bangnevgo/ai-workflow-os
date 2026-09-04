#!/usr/bin/env bash
# seed_demo.sh — isi ledger dengan skenario contoh dari NEVGO_WORKFLOW_PRACTICAL.md
#
# Cara pakai:  bash tools/seed_demo.sh        (jalankan dari root repo ~/nevgo)
# Menghapus semua data yang sudah ada lalu membangun riwayat demo + BOARD.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export NEVGO_HOME="$ROOT"
W="$ROOT/workflow"
WEB="$ROOT/divisions/website"
MKT="$ROOT/divisions/marketing"
OPS="$ROOT/divisions/operasional"

# ---- mulai bersih -------------------------------------------------------
"$W" wipe --yes --actor owner >/dev/null 2>&1
export NEVGO_NO_GIT=1      # satu commit di akhir, bukan per baris

chk() { # desc, expected_exit, dir, cmd...
  local desc="$1" want="$2" dir="$3"; shift 3
  local out rc
  out="$(cd "$dir" && "$@" 2>&1)"; rc=$?
  echo ""
  echo "### $desc"
  echo "$out" | sed 's/^/    /'
  if [ "$rc" -eq "$want" ]; then
    echo "    -> exit $rc (sesuai)"
  else
    echo "    !! exit $rc, diharapkan $want"
    exit 1
  fi
}

chk "1. Agen divisi Website menandai mulai (aktor: platform-a)" 0 "$WEB" "$W" submit \
  --project checkout-redesign --status SIAP-JALAN --actor platform-a

chk "2. Platform berbeda dua hari kemudian 'mengerjakan ulang' tanpa tahu" 0 "$WEB" "$W" submit \
  --project checkout-redesign --status SIAP-JALAN --actor platform-b

chk "3. Marketing menyiapkan copy (platform-c), lalu dijalankan" 0 "$MKT" "$W" submit \
  --project promo-harbolnas --status SIAP-JALAN --actor platform-c
chk "4. Marketing mulai kerja" 0 "$MKT" "$W" submit \
  --project promo-harbolnas --status BERJALAN --actor platform-c

chk "5. Website mencatat dependency: butuh copy promo dulu" 0 "$WEB" "$W" depend add \
  --project checkout-redesign --depends-on marketing/promo-harbolnas \
  --reason "halaman checkout menampilkan copy & CTA dari promo harbolnas"

chk "6. Website klaim SELESAI padahal promo belum selesai -> DITAHAN (exit 3)" 3 "$WEB" "$W" submit \
  --project checkout-redesign --status SELESAI \
  --evidence "url live: checkout.nevgo.id, screenshot terlampir" \
  --verification "curl -I checkout.nevgo.id -> 200 OK, dicek manual"

chk "7. Marketing selesai dengan evidence + verification (minta bantuan cc konten)" 0 "$MKT" "$W" submit \
  --project promo-harbolnas --status SELESAI \
  --evidence "landing promo live di /promo-harbolnas, hasil uji A/B lampiran" \
  --verification "curl -I nevgo.id/promo-harbolnas -> 200; dicek dua browser" \
  --cc konten:katalog-produk

chk "8. Sekarang closing website lolos (dependency terpenuhi)" 0 "$WEB" "$W" submit \
  --project checkout-redesign --status SELESAI \
  --evidence "url live: checkout.nevgo.id, screenshot terlampir" \
  --verification "curl -I checkout.nevgo.id -> 200 OK, dicek manual"

chk "9. Kirim status sama dua kali -> no-op, tidak ada duplikat" 0 "$WEB" "$W" submit \
  --project checkout-redesign --status SELESAI \
  --evidence "url live: checkout.nevgo.id" \
  --verification "curl -> 200"

chk "10. Agen mencoba SELESAI TANPA evidence -> DITOLAK (exit 2)" 2 "$OPS" "$W" submit \
  --project pindah-server --status SELESAI --actor platform-d

chk "11. Agen di operasional coba menutup proyek divisi website (kepemilikan kabur)" 0 "$OPS" "$W" submit \
  --project checkout-redesign --status BERJALAN --actor platform-e

chk "12. Agen non-owner mencoba paksa --override -> DITOLAK (exit 2)" 2 "$WEB" "$W" submit \
  --project launch-page --status SELESAI --override --reason "katanya urgent" \
  --evidence "halaman live" --verification "sudah dicek"

chk "13. Owner menemukan masalah setelah 'selesai' -> reopen" 0 "$WEB" "$W" reopen \
  --project checkout-redesign --actor owner \
  --reason "pembayaran gagal di uji nyata, perlu perbaikan gateway"

chk "14. Proyek baru menunggu checkout yang sedang dibuka lagi" 0 "$WEB" "$W" submit \
  --project launch-page --status SIAP-JALAN --actor platform-a
chk "15. ... dan mencatat dependency ke checkout-redesign" 0 "$WEB" "$W" depend add \
  --project launch-page --depends-on checkout-redesign \
  --reason "CTA launch-page membawa user ke checkout"

chk "16. closing launch-page ditahan (checkout belum selesai lagi)" 3 "$WEB" "$W" submit \
  --project launch-page --status SELESAI \
  --evidence "url live: nevgo.id/launch, diuji di 3 browser" \
  --verification "curl -I nevgo.id/launch -> 200; cek klik CTA manual"

chk "17. Owner rekonsiliasi: risiko diterima, tutup dengan --override" 0 "$WEB" "$W" submit \
  --project launch-page --status SELESAI \
  --evidence "url live: nevgo.id/launch, diuji di 3 browser" \
  --verification "curl -I nevgo.id/launch -> 200; cek klik CTA manual" \
  --override --actor owner \
  --reason "risiko diterima: CTA sudah live dan arah checkout diperbaiki akhir minggu"

chk "18. Catatan bebas 'selesai tapi perlu dicek lagi' bukan status" 0 "$WEB" "$W" note \
  --project launch-page \
  --message "perlu dicek lagi banner promo setelah harbolnas turun minggu depan (catatan, bukan status)"

chk "19. Cek integritas hash-chain semua ledger" 0 "$ROOT" "$W" verify

unset NEVGO_NO_GIT
(cd "$ROOT" && "$W" board --write)
(cd "$ROOT" && "$W" commit --message "seed demo: skenario multi-platform")

echo ""
echo "Selesai. Coba:"
echo "  cd $ROOT && ./workflow status --json"
echo "  cd $ROOT && ./workflow rejections"
echo "  cat $ROOT/BOARD.md"
