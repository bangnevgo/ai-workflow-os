#!/usr/bin/env bash
# Uji otomatis prototipe nevgo-workflow. Root sementara (tidak menyentuh ~/nevgo).
set -u

T=$(mktemp -d /tmp/nevgo-test.XXXXXX)
export NEVGO_HOME="$T"
W="/home/user/nevgo/workflow"
PASS=0; FAIL=0

t() { # desc, expect_rc, cmd...
  local desc="$1" want="$2"; shift 2
  local out rc
  out="$("$@" 2>&1)"; rc=$?
  if [ "$rc" -eq "$want" ]; then
    PASS=$((PASS+1)); echo "ok   ($rc) $desc"
  else
    FAIL=$((FAIL+1)); echo "FAIL ($rc != $want) $desc"
    echo "$out" | sed 's/^/     /'
  fi
}

# --- persiapan ----------------------------------------------------------------
"$W" init >/dev/null 2>&1
D="$T/divisions/website"; M="$T/divisions/marketing"

# --- kepemilikan dari folder ----------------------------------------------------
t "whoami di luar divisi = error (untuk preflight agen)" 1 "$W" whoami
t "submit di dalam divisi website jalan (divisi dari cwd)" 0 bash -c "cd '$D' && '$W' submit --project a --status DISIAPKAN"

# --- state machine ----------------------------------------------------------------
t "status tidak dikenal ditolak" 2 bash -c "cd '$D' && '$W' submit --project x --status NYARIS"
t "SELESAI dari IDE ditolak (state)" 2 bash -c "cd '$D' && '$W' submit --project x --status SELESAI"
t "SIAP-JALAN dari IDE diterima" 0 bash -c "cd '$D' && '$W' submit --project x --status SIAP-JALAN"
t "SELESAI tanpa evidence ditolak" 2 bash -c "cd '$D' && '$W' submit --project x --status SELESAI --evidence 'url'"
t "SELESAI dengan evidence+verification diterima" 0 bash -c "cd '$D' && '$W' submit --project x --status SELESAI --evidence 'url live: checkout.nevgo.id' --verification 'curl -I -> 200 OK, dicek manual'"
t "submit status sama = no-op (anti-duplikat)" 0 bash -c "cd '$D' && '$W' submit --project x --status SELESAI --evidence 'url' --verification 'cek'"
t "mundur dari SELESAI tanpa reopen ditolak" 2 bash -c "cd '$D' && '$W' submit --project x --status BERJALAN"
t "reopen non-owner ditolak" 2 bash -c "cd '$D' && '$W' reopen --project x --actor platform-a --reason 'ada masalah'"
t "reopen owner diterima" 0 bash -c "cd '$D' && '$W' reopen --project x --actor owner --reason 'bug ditemukan di uji nyata'"
t "kembali ke IDE ditolak" 2 bash -c "cd '$D' && '$W' submit --project x --status IDE"

# --- dependency hold --------------------------------------------------------------
t "dependency dicatat" 0 bash -c "cd '$D' && '$W' depend add --project x --depends-on y --reason 'x butuh y dulu'"
t "closing x ditahan karena y belum SELESAI" 3 bash -c "cd '$D' && '$W' submit --project x --status SELESAI --evidence 'url' --verification 'curl ok'"
t "depend remove non-owner ditolak" 2 bash -c "cd '$D' && '$W' depend remove --project x --depends-on y --actor platform-a --reason 'tidak perlu lagi'"
t "override non-owner ditolak" 2 bash -c "cd '$D' && '$W' submit --project x --status SELESAI --override --actor platform-a --reason 'urgent' --evidence 'url' --verification 'cek'"
t "closing x lolos setelah y SELESAI" 0 bash -c "cd '$D' && '$W' submit --project y --status SIAP-JALAN && '$W' submit --project y --status SELESAI --evidence 'url' --verification 'cek' && '$W' submit --project x --status SELESAI --evidence 'url' --verification 'cek'"

# --- append-only & integritas -------------------------------------------------------
LED="$T/.workflow/ledger/website.jsonl"
printf '{"rusak\n' >> "$LED"
COUNT_CORRUPT=$(wc -l < "$LED")
t "verify mendeteksi korupsi" 1 "$W" verify
t "submit menolak menulis saat ledger korup" 1 bash -c "cd '$D' && '$W' submit --project z --status BERJALAN"
AFTER=$(wc -l < "$LED")
if [ "$AFTER" -eq "$COUNT_CORRUPT" ]; then
  PASS=$((PASS+1)); echo "ok   tidak ada byte tertulis saat store korup (tetap $AFTER baris)"
else
  FAIL=$((FAIL+1)); echo "FAIL byte tertulis saat store korup ($COUNT_CORRUPT -> $AFTER)"
fi
(cd "$T" && git checkout -- .workflow/ledger/website.jsonl >/dev/null 2>&1)
t "verify pulih setelah git checkout (ledger = sumber kebenaran)" 0 "$W" verify

# --- cc tidak mengeksekusi ------------------------------------------------------------
t "cc lintas divisi dicatat, tidak dieksekusi" 0 bash -c "cd '$M' && '$W' submit --project k --status SIAP-JALAN --cc website:y"
t "cc divisi tak dikenal ditolak" 2 bash -c "cd '$M' && '$W' submit --project k --status BERJALAN --cc nggakada:z"

# --- journal penolakan ------------------------------------------------------------------
t "journal penolakan berisi kejadian" 0 bash -c "cd '$D' && '$W' rejections"

# --- BOARD (view turunan) -----------------------------------------------------------------
t "BOARD bisa dibangun ulang" 0 "$W" board --write
[ -f "$T/BOARD.md" ] && { PASS=$((PASS+1)); echo "ok   BOARD.md dibuat"; } || { FAIL=$((FAIL+1)); echo "FAIL BOARD.md tidak dibuat"; }

echo ""
echo "Hasil: $PASS lulus, $FAIL gagal"
rm -rf "$T"
[ "$FAIL" -eq 0 ]
