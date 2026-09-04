#!/usr/bin/env python3
"""
nevgo-workflow — satu jalur tulis untuk semua platform AI & semua divisi.

Prinsip (lihat README.md dan NEVGO_WORKFLOW_PRACTICAL.md):
  1. Tidak ada status yang tercatat kecuali lewat CLI ini.
  2. Divisi ditentukan dari working directory, bukan dari klaim model.
  3. Transisi ke SELESAI dikunci ketat: butuh evidence + verification
     dan tidak boleh ada dependency terbuka (kecuali owner override).
  4. Ledger per divisi = append-only, dirantai hash, di-track git.
     BOARD hanyalah view turunan yang dibangun ulang dari ledger.
  5. Penolakan dicatat sebagai data terpisah (bukan cuma di terminal).

Dibangun untuk Linux/macOS. Python >= 3.9, stdlib saja.
"""

import argparse
import contextlib
import datetime
import fcntl
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

VERSION = "0.1.0"

# ----------------------------------------------------------------------------
# Nama & konstanta
# ----------------------------------------------------------------------------

STATES_DEFAULT = ["IDE", "DISIAPKAN", "SIAP-JALAN", "BERJALAN", "SELESAI"]
SLUG_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,79}$")

EX_OK = 0
EX_ERR = 1
EX_REJECT = 2        # ditolak validator (exit ini agar otomasi bisa baca kegagalan)
EX_HELD = 3          # closing ditahan dependency

DEFAULT_OWNER_ACTORS = ["owner"]

DEFAULT_DIVISIONS = {
    "konten":     {"dir": "divisions/konten",     "label": "Konten"},
    "marketing":  {"dir": "divisions/marketing",  "label": "Marketing"},
    "operasional": {"dir": "divisions/operasional", "label": "Operasional"},
    "penjualan":  {"dir": "divisions/penjualan",  "label": "Penjualan"},
    "keuangan":   {"dir": "divisions/keuangan",   "label": "Keuangan"},
    "website":    {"dir": "divisions/website",    "label": "Website"},
}

DEFAULT_POLICY = {
    "evidence_min_len": 3,
    "verification_min_len": 3,
    "require_evidence_for": ["SELESAI"],
    "require_verification_for": ["SELESAI"],
    "selesai_min_from": ["SIAP-JALAN", "BERJALAN"],
    "dep_hold_policy": "any",          # "any" | "outgoing"
    "max_cc": 5,
    "memory_index_max_lines": 200,     # cap INDEX.md memori terkompilasi (dream)
}


def _red(t): return "\033[31m" + t + "\033[0m"
def _grn(t): return "\033[32m" + t + "\033[0m"
def _yel(t): return "\033[33m" + t + "\033[0m"
def _dim(t): return "\033[2m" + t + "\033[0m"
def _bld(t): return "\033[1m" + t + "\033[0m"

def _colorize():
    """Hanya aktif kalau output terminal (bukan pipe/file)."""
    return sys.stdout.isatty() and sys.stderr.isatty()


def c_red(s):
    return _red(s) if _colorize() else s
def c_grn(s):
    return _grn(s) if _colorize() else s
def c_yel(s):
    return _yel(s) if _colorize() else s
def c_dim(s):
    return _dim(s) if _colorize() else s
def c_bld(s):
    return _bld(s) if _colorize() else s


class WorkflowError(Exception):
    pass

class IntegrityError(WorkflowError):
    pass

class Rejected(WorkflowError):
    """Ditolak validator — akan dicatat di journal penolakan."""

    def __init__(self, reasons, held=False):
        self.reasons = reasons          # list of (tag, message)
        self.held = held
        super().__init__("; ".join(msg for _, msg in reasons))


# ----------------------------------------------------------------------------
# Path & konfigurasi
# ----------------------------------------------------------------------------

def resolve_root():
    r = os.environ.get("NEVGO_HOME")
    if not r:
        r = os.path.expanduser("~/nevgo")
    return os.path.abspath(r)


def config_path(root):
    return os.path.join(root, "config.json")


def load_config(root):
    p = config_path(root)
    if not os.path.exists(p):
        raise WorkflowError(
            f"Belum ada konfigurasi di {p}.\n"
            f"Jalankan dulu: workflow init  (root: {root})")
    with open(p, encoding="utf-8") as f:
        cfg = json.load(f)
    cfg.setdefault("owner_actors", DEFAULT_OWNER_ACTORS)
    cfg.setdefault("divisions", DEFAULT_DIVISIONS)
    cfg.setdefault("states", STATES_DEFAULT)
    cfg.setdefault("policy", DEFAULT_POLICY)
    pol = cfg["policy"]
    for k, v in DEFAULT_POLICY.items():
        pol.setdefault(k, v)
    return cfg


def state_index(cfg):
    return {s: i for i, s in enumerate(cfg["states"])}


def norm_state(raw):
    """Terima 'SIAP JALAN' / 'siap_jalan' / 'siap-jalan' -> token kanonik."""
    if not raw:
        return None
    s = str(raw).upper().replace("_", "-").replace(" ", "-")
    return s


def division_dir(root, cfg, div):
    return os.path.join(root, cfg["divisions"][div]["dir"])


def division_from_cwd(cfg, root, cwd=None):
    """Divisi ditentukan dari working directory — dari luar model, bukan klaim agen."""
    cwd = os.path.realpath(cwd or os.getcwd())
    root_r = os.path.realpath(root)
    best = None
    best_len = -1
    for div in cfg["divisions"]:
        d = os.path.realpath(division_dir(root, cfg, div))
        if not os.path.exists(d):
            continue
        if cwd == d or cwd.startswith(d + os.sep):
            if len(d) > best_len:
                best_len = len(d)
                best = div
    return best


def qname(div, project):
    return f"{div}/{project}"


# ----------------------------------------------------------------------------
# Penyimpanan: ledger & rejections (append-only, hash-chain)
# ----------------------------------------------------------------------------

def store_dir(root, kind):
    # kind: "ledger" | "rejections"
    return os.path.join(root, ".workflow", kind)


def store_path(root, div, kind):
    return os.path.join(store_dir(root, kind), f"{div}.jsonl")


def head_path(root, div, kind):
    return store_path(root, div, kind) + ".head"


def _h(b):
    return hashlib.sha256(b).hexdigest()


def _ts():
    return datetime.datetime.now().astimezone().isoformat(timespec="seconds")


def _read_lines(path):
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as f:
        return f.read().splitlines()


def _chain_problem(lines):
    """Cek keterkaitan hash (prev) & nomor urut (seq). Return msg atau None."""
    for i, ln in enumerate(lines):
        try:
            obj = json.loads(ln)
        except Exception:
            return f"baris ke-{i + 1} bukan JSON valid"
        exp = i + 1
        if obj.get("seq") != exp:
            return f"baris ke-{i + 1}: seq {obj.get('seq')} != {exp} (histori tak berurutan?)"
        if i > 0:
            want = _h(lines[i - 1].encode("utf-8"))
            if obj.get("prev") != want:
                return f"rantai hash putus di baris ke-{i + 1} (histori pernah diubah?)"
    return None


def verify_store(root, div, kind, heal=True):
    """Verifikasi chain + head pointer. Return (ok, pesan)."""
    p = store_path(root, div, kind)
    lines = _read_lines(p)
    prob = _chain_problem(lines) if lines else None
    if prob:
        return False, prob
    hp = head_path(root, div, kind)
    if lines:
        last_h = _h(lines[-1].encode("utf-8"))
        if os.path.exists(hp):
            try:
                head_val = open(hp, encoding="utf-8").read().strip()
            except OSError:
                head_val = None
            if head_val != last_h:
                # Kemungkinan crash di antara append baris & tulis head:
                # baris terakhir tetap valid & konsisten -> auto-heal bila
                # head menunjuk ke baris sebelumnya.
                if len(lines) >= 2 and head_val == _h(lines[-2].encode("utf-8")):
                    if heal:
                        _write_head(hp, last_h)
                        return True, "auto-heal head pointer (1 baris baru tersisa dari crash)"
                    return True, "head tertinggal satu baris (auto-heal jika diizinkan)"
                return False, "head pointer tidak cocok dengan baris terakhir"
        else:
            # tidak ada head sama sekali padahal ada isi: simpan sekarang
            if heal:
                _write_head(hp, last_h)
                return True, "head pointer dibuat ulang"
            return True, "head pointer belum ada"
    else:
        if os.path.exists(hp):
            if heal:
                os.remove(hp)
                return True, "head pointer dihapus (ledger kosong)"
            return True, "head pointer basi (ledger kosong)"
    return True, "ok"


def _write_head(path, val):
    d = os.path.dirname(path)
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=d)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(val)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.remove(tmp)
        except OSError:
            pass
        raise


@contextlib.contextmanager
def _file_lock(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as lk:
        fcntl.flock(lk, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(lk, fcntl.LOCK_UN)


def lock_path(root, div, kind):
    return os.path.join(root, ".workflow", "locks", f"{kind}-{div}.lock")


def append_entry(root, div, kind, payload, actor="manual"):
    """
    Tulis satu baris ke store (ledger/rejections). Satu-satunya jalur tulis.
    Memvalidasi rantai hash lebih dulu; kalau korup, tidak ada byte tertulis.
    """
    os.makedirs(store_dir(root, kind), exist_ok=True)
    with _file_lock(lock_path(root, div, kind)):
        p = store_path(root, div, kind)
        lines = _read_lines(p)
        prob = _chain_problem(lines) if lines else None
        if prob:
            raise IntegrityError(
                f"LEDGER {div} ({kind}) KORUP: {prob}\n"
                f"Tidak ada yang ditulis. Ledger tetap sumber kebenaran:\n"
                f"  workflow verify\n"
                f"  git -C {root} log --oneline\n"
                f"  git -C {root} checkout -- .workflow/{kind}/{div}.jsonl")
        seq = len(lines) + 1
        prev = _h(lines[-1].encode("utf-8")) if lines else None
        rec = {
            "seq": seq,
            "ts": _ts(),
            "kind": payload.pop("kind"),
            "div": div,
            "actor": payload.pop("actor", actor) or actor,
        }
        rec.update(payload)
        rec["prev"] = prev
        line = json.dumps(rec, ensure_ascii=False, sort_keys=True) + "\n"
        with open(p, "a", encoding="utf-8") as f:
            f.write(line)
            f.flush()
            os.fsync(f.fileno())
        _write_head(head_path(root, div, kind), _h(line.rstrip("\n").encode("utf-8")))
    return rec


def read_entries(root, div, kind="ledger", strict=True):
    """Baca semua entry store tertentu. Kalau korup, raise IntegrityError —
    supaya tidak ada pemakai store yang diam-diam melihat data menyesatkan."""
    p = store_path(root, div, kind)
    if not os.path.exists(p):
        return []
    ok, msg = verify_store(root, div, kind, heal=False)
    if not ok:
        raise IntegrityError(f"store {div}/{kind} korup: {msg}")
    out = []
    for ln in _read_lines(p):
        try:
            out.append(json.loads(ln))
        except Exception:
            raise IntegrityError(f"store {div}/{kind} berisi baris non-JSON")
    return out


# ----------------------------------------------------------------------------
# Status proyek & edge dependency
# ----------------------------------------------------------------------------

def compute_states(entries):
    """
    Dari urutan entry, tentukan status terakhir tiap proyek.
    Entry yang mengubah status: kind=submit (to), kind=reopen (-> BERJALAN).
    Proyek yang belum punya status = IDE (dasar).
    """
    st = {}
    for e in entries:
        k = e.get("kind")
        proj = e.get("project")
        if not proj:
            continue
        if k in ("submit", "override") and e.get("to"):
            st[proj] = {"state": e["to"], "ts": e.get("ts"), "seq": e.get("seq")}
        elif k == "reopen" and proj in st:
            st[proj] = {"state": "BERJALAN", "ts": e.get("ts"), "seq": e.get("seq")}
    return st


def _all_project_names(entries):
    names = []
    seen = set()
    for e in entries:
        p = e.get("project")
        if p and p not in seen:
            seen.add(p)
            names.append(p)
    return names


def state_of(entries, project):
    return compute_states(entries).get(project, {}).get("state")


def read_edges(root, cfg, div):
    """Edge dependency yang tercatat di ledger divisi ini.
    Pasangan (div,project)->(dep_div,dep_project). Return list open & all."""
    entries = read_entries(root, div, strict=False)
    order = {}   # key -> dep entry (yang membuka)
    closed = {}  # key -> dep-remove entry
    key_of = {}
    for e in entries:
        k = e.get("kind")
        if k not in ("dep", "dep-remove"):
            continue
        key = (e["project"], e.get("dep_div"), e.get("dep_project"))
        key_of[key] = key
        if k == "dep":
            order[key] = e
            closed.pop(key, None)
        else:
            closed[key] = e
            order.pop(key, None)
    return order, closed


def all_open_edges(root, cfg):
    """Open edges di semua divisi. tiap item dict penuh."""
    out = []
    for div in cfg["divisions"]:
        order, _ = read_edges(root, cfg, div)
        for key, e in sorted(order.items(), key=lambda kv: (kv[1].get("ts"), kv[1].get("seq"))):
            out.append(e)
    return out


def counterpart(e):
    # entry dep di ledger si dependen (X): project=X, dep_* = yang ditunggu.
    from_q = qname(e.get("div"), e.get("project"))
    to_q = qname(e.get("dep_div"), e.get("dep_project"))
    return from_q, to_q


def incident_open_edges(root, cfg, div, project):
    """Semua open edge yang menyentuh qname ini (masuk atau keluar)."""
    target = qname(div, project)
    res = []
    for e in all_open_edges(root, cfg):
        fq, tq = counterpart(e)
        if fq == target or tq == target:
            res.append(e)
    return res


def _qname_state(root, cfg, q):
    d, p = q.split("/", 1)
    if d not in cfg["divisions"]:
        return None
    entries = read_entries(root, d, strict=False)
    return state_of(entries, p)


# ----------------------------------------------------------------------------
# Validator state machine
# ----------------------------------------------------------------------------

class Decision:
    def __init__(self):
        self.action = None          # noop | reject | held | ok
        self.reasons = []           # list (tag, msg)
        self.held = False
        self.info = {}


def validate_submit(root, cfg, args, div, current):
    """
    current: (state, has_history) — has_history False berarti proyek baru/IDE tanpa entry.
    Mengembalikan Decision.
    """
    st = state_index(cfg)
    dec = Decision()
    to = args.status
    now = current[0] or "IDE"
    has_history = current[1]

    if to == now:
        dec.action = "noop"
        return dec

    i_to, i_now = st[to], st[now]

    # --- aturan umum -------------------------------------------------------
    if not has_history and to == "IDE":
        dec.reasons.append(("state", "status awal sudah IDE; submit status lain dulu"))
        dec.action = "reject"
        return dec

    if to == "IDE":
        dec.reasons.append(("state", "tidak bisa kembali ke IDE; tulis catatan bebas via 'workflow note'"))
        dec.action = "reject"
        return dec

    if i_to < i_now:
        if now == "SELESAI":
            dec.reasons.append(("state", "keluar dari SELESAI hanya lewat 'workflow reopen' (khusus owner)"))
        else:
            # mundur di antara status aktif diizinkan — "yang lain lebih longgar"
            pass
        if dec.reasons:
            dec.action = "reject"
            return dec

    # --- gerbang khusus SELESAI -------------------------------------------
    if to == "SELESAI":
        if now not in cfg["policy"]["selesai_min_from"]:
            dec.reasons.append(("state",
                f"ke SELESAI dari '{now}' tidak diizinkan; harus lewat "
                f"{' / '.join(cfg['policy']['selesai_min_from'])} dulu"))
        ev = (args.evidence or "").strip()
        ve = (args.verification or "").strip()
        if "SELESAI" in cfg["policy"]["require_evidence_for"] and len(ev) < cfg["policy"]["evidence_min_len"]:
            dec.reasons.append(("evidence",
                "SELESAI butuh --evidence konkret (url / screenshot / hasil test), bukan klaim"))
        if "SELESAI" in cfg["policy"]["require_verification_for"] and len(ve) < cfg["policy"]["verification_min_len"]:
            dec.reasons.append(("verification",
                "SELESAI butuh --verification (cara klaim itu diperiksa, mis. 'curl -I -> 200 OK')"))

    # --- requirement evidence untuk status lain (jika policy meminta) ------
    ev = (args.evidence or "").strip()
    ve = (args.verification or "").strip()
    for req in cfg["policy"]["require_evidence_for"]:
        if req == to and len(ev) < cfg["policy"]["evidence_min_len"]:
            dec.reasons.append(("evidence", f"status {to} butuh --evidence"))
    for req in cfg["policy"]["require_verification_for"]:
        if req == to and len(ve) < cfg["policy"]["verification_min_len"]:
            dec.reasons.append(("verification", f"status {to} butuh --verification"))

    # --- dependency hold ----------------------------------------------------
    # Yang menahan closing X = dependensi KELUAR X yang belum tuntas
    # (X → Y, Y belum SELESAI). Proyek yang menunggu X TIDAK menahan X.
    if to == "SELESAI" and not args.override:
        target_q = qname(div, args.project)
        blockers = []
        for e in all_open_edges(root, cfg):
            fq, tq = counterpart(e)
            if fq != target_q:      # hanya edge di mana proyek ini dependen
                continue
            if _qname_state(root, cfg, tq) != "SELESAI":
                blockers.append(f"{tq} (belum SELESAI; dibuka {e.get('actor')})")
        if blockers:
            dec.held = True
            dec.reasons.append(("hold",
                "closing ditahan otomatis sampai direkonsiliasi — masih ada proyek yang "
                "belum selesai terkait lewat dependency:\n      - "
                + "\n      - ".join(blockers)
                + "\n      Rekonsiliasi manual oleh owner: selesaikan proyek itu, "
                  "'workflow depend remove', atau submit dengan --override --reason ..."))

    if dec.reasons:
        if dec.action != "reject":
            dec.action = "held" if dec.held else "reject"
        return dec

    dec.action = "ok"
    dec.info = {"from": now}
    return dec


def format_rejections(e):
    r = e.get("reasons") or []
    if isinstance(r, list) and r and isinstance(r[0], list):
        r = [x[1] if isinstance(x, list) else x for x in r]
    if isinstance(r, str):
        r = [r]
    return r


# ----------------------------------------------------------------------------
# Presentasi: tabel sederhana
# ----------------------------------------------------------------------------

def _trunc(s, n):
    s = re.sub(r"\s+", " ", (s or "").strip())
    return s if len(s) <= n else s[: n - 1] + "…"


def _fmt_table(header, rows):
    if not rows:
        return c_dim("  (kosong)")
    cols = len(header)
    widths = [len(h) for h in header]
    for r in rows:
        for i in range(cols):
            widths[i] = max(widths[i], len(str(r[i])))
    sep = "  " + "+".join("-" * (w + 2) for w in widths)
    line = "  " + "|".join(" " + str(c).ljust(w) + " " for c, w in zip(header, widths))
    out = [line, sep]
    for r in rows:
        out.append("  " + "|".join(" " + str(c).ljust(w) + " " for c, w in zip(r, widths)))
    return "\n".join(out)


# ============================================================================
# DREAM — konsolidasi pengalaman sesi menjadi memori terkompilasi
# ----------------------------------------------------------------------------
# Analogi pola "Memory & Dreaming" (Karpathy wiki / compiled knowledge):
#   - Lapisan episodik  = ledger per divisi + journal penolakan (append-only)
#   - Dream (compile)   = job out-of-band: baca sinyal terkini, TIDAK mengubah
#                         input, hasil = PROPOSAL di .workflow/dreams/proposals/
#   - Gerbang manusia   = owner review lalu promote/reject (dicatat di journal)
#   - Memori semantik   = .workflow/memory/ yang dibaca agen saat sesi mulai
# Empat fase: Orient -> Gather Recent Signal -> Consolidate -> Prune & Index.
# ============================================================================

def dreams_root(root, sub=None):
    base = os.path.join(root, ".workflow", "dreams")
    if sub is None:
        return base
    return os.path.join(base, sub)


def proposals_dir(root):
    return dreams_root(root, "proposals")


def memory_dir(root):
    return dreams_root(root, "memory")   # live memory ter-promote


def dream_id():
    now = datetime.datetime.now(datetime.timezone.utc)
    return f"dream-{now:%Y%m%d-%H%M%S}-{hashlib.sha256(os.urandom(8)).hexdigest()[:6]}"


def _now_str():
    return datetime.datetime.now().astimezone().isoformat(timespec="seconds")


def dream_window_cutoff(hours):
    if not hours:
        return None
    return datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=hours)


def _ts_in_window(ts, cutoff):
    if cutoff is None or not ts:
        return True
    try:
        return datetime.datetime.fromisoformat(ts) >= cutoff
    except ValueError:
        return True


def _ledger_events(root, cfg, cutoff):
    """Kumpulkan event ledger seluruh divisi (+window), deterministik."""
    evs = []
    for div in cfg["divisions"]:
        for e in read_entries(root, div, strict=False):
            if e.get("kind") in ("submit", "reopen", "override", "dep", "dep-remove", "note") \
               and _ts_in_window(e.get("ts"), cutoff):
                evs.append(e)
    evs.sort(key=lambda e: (e.get("ts", ""), e.get("div", ""), e.get("seq", 0)))
    return evs


def _reject_events(root, cfg, cutoff):
    evs = []
    for div in cfg["divisions"]:
        for e in read_entries(root, div, kind="rejections", strict=False):
            if _ts_in_window(e.get("ts"), cutoff):
                evs.append(e)
    evs.sort(key=lambda e: (e.get("ts", ""), e.get("div", ""), e.get("seq", 0)))
    return evs


LESSON_TEXT = {
    "state": "transisi status tidak sah (mis. SELESAI langsung dari IDE) — wajib lewat SIAP-JALAN/BERJALAN",
    "evidence": "klaim SELESAI tanpa bukti konkret — selalu bawa --evidence (url / screenshot / hasil test)",
    "verification": "klaim SELESAI tanpa cara memeriksa — selalu bawa --verification (mis. curl -I -> 200 OK)",
    "owner": "mencoba operasi khusus owner (override/reopen/remove depend) — itu hak owner",
    "hold": "closing ditahan dependency terbuka — cek `workflow depend list` sebelum klaim SELESAI",
    "format": "format argumen salah (--reason/--override) — ikuti `workflow states`",
}


def _reason_messages(e):
    rs = e.get("reasons") or []
    out = []
    for r in rs:
        if isinstance(r, list) and len(r) == 2:
            out.append(r[1] if isinstance(r[1], str) else str(r[1]))
        elif isinstance(r, str):
            out.append(r)
    return out


def _qstate(root, cfg, q):
    try:
        d, p = q.split("/", 1)
        entries = read_entries(root, d, strict=False)
        return state_of(entries, p) or "IDE"
    except Exception:
        return "?"


# ---- ringkas dokumen proposal ---------------------------------------------

def doc_state(root, cfg, evs):
    L = ["# ORIENT — state saat ini (snapshot, bukan histori)",
         "",
         f"_Dibuat {_now_str()} oleh dream run. Sumber: ledger per divisi._",
         ""]
    for div in cfg["divisions"]:
        entries = read_entries(root, div, strict=False)
        states = compute_states(entries)
        names = [p for p in _all_project_names(entries)]
        if not names:
            continue
        L.append(f"## Divisi {cfg['divisions'][div]['label']} ({div})")
        for p in names:
            info = states.get(p, {})
            L.append(f"- **{qname(div, p)}** — {info.get('state') or 'IDE'}  "
                     f"(update {(info.get('ts') or '')[:16]})")
        L.append("")
    if all(not _all_project_names(read_entries(root, d, strict=False))
           for d in cfg["divisions"]):
        L.append("_Belum ada proyek tercatat._")
    return "\n".join(L)


def doc_projects(root, cfg, evs, cutoff):
    L = ["# PROJECTS — konteks terkompilasi per proyek",
         "",
         f"_Dibuat {_now_str()}. Evidence/verification diambil dari entry terakhir "
         f"yang menyediakannya._",
         ""]
    open_edges = all_open_edges(root, cfg)
    by_dependen = {}
    for e in open_edges:
        fq, tq = counterpart(e)
        by_dependen.setdefault(fq, []).append((tq, e))
    notes_by_proj = {}
    for e in evs:
        if e.get("kind") == "note" and e.get("project"):
            notes_by_proj.setdefault(qname(e.get("div"), e["project"]), []).append(e)
    wrote = False
    for div in cfg["divisions"]:
        entries = read_entries(root, div, strict=False)
        states = compute_states(entries)
        names = _all_project_names(entries)
        if not names:
            continue
        wrote = True
        L.append(f"## {cfg['divisions'][div]['label']} (`{div}`)")
        for p in names:
            q = qname(div, p)
            state = states.get(p, {}).get("state") or "IDE"
            ev = ve = ""
            for e in reversed(entries):
                if e.get("project") != p:
                    continue
                if e.get("kind") in ("submit", "override") and not ev and e.get("evidence"):
                    ev = e["evidence"]
                if e.get("kind") in ("submit", "override") and not ve and e.get("verification"):
                    ve = e["verification"]
            deps = by_dependen.get(q, [])
            dep_txt = ""
            if deps:
                dep_txt = " menunggu: " + ", ".join(f"{t}({_qstate(root, cfg, t)})" for t, _ in deps)
            L.append(f"- **{p}** — {state}{dep_txt}")
            if ev:
                L.append(f"    evidence: {_trunc(ev, 110)}")
            if ve:
                L.append(f"    verifikasi: {_trunc(ve, 110)}")
            for n in notes_by_proj.get(q, [])[-2:]:
                L.append(f"    catatan ({n.get('actor')}): {_trunc(n.get('note'), 110)}")
        L.append("")
    if not wrote:
        L.append("_Belum ada proyek._")
    return "\n".join(L)


def doc_lessons(root, cfg, rejs, cutoff):
    L = ["# LESSONS — pola kesalahan terbaru (dari journal penolakan)",
         "",
         f"_Fase Gather: hanya kejadian penolakan dalam jendela waktu terakhir_ "
         f"(cutoff: {cutoff or 'semua waktu'}).",
         ""]
    if not rejs:
        L.append("_Tidak ada penolakan dalam jendela ini._")
        return "\n".join(L)
    # taksonomi: (div, tag) -> jumlah + contoh pertama
    tax = {}
    samples = {}
    for e in rejs:
        div = e.get("div")
        for r in e.get("reasons") or []:
            if not (isinstance(r, list) and len(r) == 2):
                continue
            tag = r[0]
            key = (div, tag)
            tax[key] = tax.get(key, 0) + 1
            samples.setdefault(key, (e.get("project"), e.get("requested_status"), e.get("actor")))
    for (div, tag), n in sorted(tax.items(), key=lambda kv: (-kv[1], kv[0])):
        txt = LESSON_TEXT.get(tag, f"penolakan tipe '{tag}'")
        proj, req, actor = samples[(div, tag)]
        who = f"{div}/{proj}" if proj else div
        parts = [who]
        if req:
            parts.append(f"→ {req}")
        if actor:
            parts.append(f"oleh {actor}")
        L.append(f"- [{tag}] {div}: {n}× {txt}. Contoh: {' '.join(parts)}.")
    L.append("")
    L.append("> Aturan-aturan ini hidup di validator (`workflow states`). Baris di atas "
             "hanya memberi tahu platform mana yang paling sering melanggarnya.")
    return "\n".join(L)


def doc_decisions(root, cfg, evs):
    L = ["# DECISIONS — keputusan owner yang tidak boleh dilupakan",
         "",
         "_Override & reopen tercatat di ledger (append-only). Ringkasan ini "
         "biar sesi berikutnya tidak mengulang perdebatan yang sudah diputus._",
         ""]
    dec = [e for e in evs if e.get("kind") in ("override", "reopen")]
    # sertakan keputusan lama sekalipun di luar jendela — ambil dari semua ledger
    if not dec:
        dec = []
        for div in cfg["divisions"]:
            for e in read_entries(root, div, strict=False):
                if e.get("kind") in ("override", "reopen"):
                    dec.append(e)
        dec.sort(key=lambda e: e.get("ts", ""))
    if not dec:
        L.append("_Belum ada keputusan owner (override/reopen)._")
        return "\n".join(L)
    for e in dec[-40:]:
        frm = e.get("from") or "IDE"
        L.append(f"- {e.get('ts', '')[:16]} — {qname(e.get('div'), e.get('project'))} "
                 f"{frm}→{e.get('to')} oleh {e.get('actor')}: {e.get('reason') or e.get('note') or '—'}")
    return "\n".join(L)


def doc_crosslinks(root, cfg, evs, cutoff):
    L = ["# CROSSLINKS — peta ketergantungan lintas divisi",
         "",
         "_Open edge saat ini + ringkasan cc. Mencatat ≠ mengeksekusi._",
         ""]
    edges = all_open_edges(root, cfg)
    if edges:
        for e in edges:
            fq, tq = counterpart(e)
            st = _qstate(root, cfg, tq)
            mark = "✓" if st == "SELESAI" else "✗ menunggu"
            L.append(f"- **{fq}** → {tq}  [{mark}, kini {st}] — {_trunc(e.get('reason') or '', 90)}")
    else:
        L.append("_Tidak ada dependency terbuka._")
    cc_counts = {}
    closed = 0
    for e in evs:
        if e.get("kind") == "dep-remove":
            closed += 1
        for t in e.get("cc") or []:
            cc_counts[t] = cc_counts.get(t, 0) + 1
    L.append("")
    L.append(f"_Dalam jendela: {closed} dependency ditutup._")
    if cc_counts:
        L.append("_cc lintas divisi tercatat:_ " +
                 ", ".join(f"{t} {n}×" for t, n in sorted(cc_counts.items())))
    return "\n".join(L)


def doc_agents(root, cfg, evs, rejs):
    L = ["# AGENTS — pola aktivitas per platform AI",
         "",
         "_Siapa yang bekerja, seberapa sering, dan siapa yang paling sering "
         "tertolak validator — supaya brief berikutnya bisa diarahkan._",
         ""]
    act = {}
    for e in evs:
        a = e.get("actor") or "?"
        act.setdefault(a, {"events": 0, "kinds": {}})
        act[a]["events"] += 1
        k = e.get("kind", "?")
        act[a]["kinds"][k] = act[a]["kinds"].get(k, 0) + 1
    rej_by = {}
    for e in rejs:
        a = e.get("actor") or "?"
        rej_by[a] = rej_by.get(a, 0) + 1
    if not act:
        L.append("_Belum ada aktivitas tercatat._")
    for a, info in sorted(act.items(), key=lambda kv: (-kv[1]["events"], kv[0])):
        kparts = ", ".join(f"{k}={v}" for k, v in sorted(info["kinds"].items()))
        warn = ""
        if rej_by.get(a, 0) >= 2:
            warn = "  ⚠ sering tertolak — baca `workflow rejections`"
        L.append(f"- **{a}**: {info['events']} event ({kparts}); "
                 f"penolakan: {rej_by.get(a, 0)}{warn}")
    return "\n".join(L)


def build_dream_index(state_doc, files, cap):
    """Prune & Index: index pendek yang dibaca pertama dalam sekali pandang."""
    lines = ["# MEMORY INDEX — baca dulu di awal sesi (dipromosikan via dream)",
             "",
             "Sumber: ledger + journal penolakan. Detail di file topik; yang di sini "
             "hanya sinyal yang harus dibawa dari sesi sebelumnya.",
             ""]
    # --- ringkasan status (dari doc_state) ---------------------------------
    lines.append("## Status sekarang")
    for ln in state_doc.splitlines():
        s = ln.strip()
        if s.startswith("- **"):
            lines.append("  " + s)
    # --- pelajaran teratas --------------------------------------------------
    lessons_file = next((f for f in files if f["name"] == "20-LESSONS.md"), None)
    lessons = []
    if lessons_file:
        lessons = [ln for ln in lessons_file["text"].splitlines()
                   if ln.startswith("- [")]
    lines.append("")
    lines.append("## Pelajaran (jangan ulangi)")
    if lessons:
        for ln in lessons[:cap]:
            # ringkas
            lines.append("  " + _trunc(ln, 120))
    else:
        lines.append("  _tidak ada penolakan terbaru_")
    # --- pointer -------------------------------------------------------------
    lines.append("")
    lines.append("## Baca lanjut")
    for f in files:
        if f["name"].endswith(".md"):
            lines.append(f"  - {f['name']}: {f['short']}")
    # enforce cap deterministik
    if len(lines) > cap:
        head = lines[:8]
        tail = lines[-max(3, len([l for l in lines if l.startswith('  - ')])):]
        body = [l for l in lines[8:] if l not in head and l not in tail]
        budget = cap - len(head) - len(tail)
        body = body[:max(0, budget)]
        lines = head + body + tail
        if len(lines) > cap:
            lines = lines[:cap]
            lines.append("  … (index terpotong oleh batas; cek file topik)")
    return "\n".join(lines)


def cmd_dream(args):
    """Dispatcher sub-perintah dream. Jalankan dari mana saja (root)."""
    root = args.root
    cfg = load_config(root)
    cap = int(cfg["policy"].get("memory_index_max_lines", 200))
    actor = resolve_actor(cfg, args)
    sub = args.dream_cmd

    if sub == "run":
        cutoff = dream_window_cutoff(args.since_hours if args.since_hours else None)
        evs = _ledger_events(root, cfg, cutoff)
        rejs = _reject_events(root, cfg, cutoff)
        pid = dream_id()
        d = os.path.join(proposals_dir(root), pid)
        os.makedirs(d, exist_ok=True)
        files = []
        def add(name, text, short):
            p = os.path.join(d, name)
            with open(p, "w", encoding="utf-8") as f:
                f.write(text + ("\n" if not text.endswith("\n") else ""))
            files.append({"name": name, "short": short, "text": text})

        state_doc = doc_state(root, cfg, evs)
        add("00-STATE.md", state_doc,
            "snapshot status seluruh divisi")
        proj_doc = doc_projects(root, cfg, evs, cutoff)
        add("10-PROJECTS.md", proj_doc,
            "konteks terkompilasi per proyek (evidence, depend, catatan)")
        less_doc = doc_lessons(root, cfg, rejs, cutoff)
        add("20-LESSONS.md", less_doc,
            "pola kesalahan dari journal penolakan")
        add("30-DECISIONS.md", doc_decisions(root, cfg, evs),
            "keputusan owner (override/reopen) + alasan")
        add("40-CROSSLINKS.md", doc_crosslinks(root, cfg, evs, cutoff),
            "peta dependency lintas divisi")
        add("50-AGENTS.md", doc_agents(root, cfg, evs, rejs),
            "pola aktivitas per platform")
        idx = build_dream_index(state_doc, files, cap)
        with open(os.path.join(d, "INDEX.md"), "w", encoding="utf-8") as f:
            f.write(idx)
        manifest = {
            "id": pid, "ts": _now_str(), "actor": actor,
            "since_hours": args.since_hours or 0,
            "counts": {"ledger_events": len(evs), "rejections": len(rejs)},
            "files": [f["name"] for f in files] + ["INDEX.md"],
        }
        with open(os.path.join(d, "manifest.json"), "w", encoding="utf-8") as f:
            json.dump(manifest, f, ensure_ascii=False, indent=2)
        try:
            append_entry(root, "journal", "dreams", {
                "kind": "dream-run", "project": pid, "actor": actor,
                "note": f"run dream ({len(evs)} event, {len(rejs)} penolakan)",
            }, actor=actor)
        except WorkflowError:
            pass   # proposal tetap ada; journal tidak wajib
        print(c_grn(f"DREAM {pid} dibuat oleh {actor}"))
        print(c_dim(f"  fase: orient → gather ({manifest['counts']}) → consolidate "
                    f"→ prune & index (cap {cap} baris)"))
        print(c_dim(f"  input ledger/rejections TIDAK diubah — ini proposal."))
        print(f"  {d}/")
        print("  Review:  workflow dream review " + pid)
        print("  Promote: workflow dream promote " + pid + " --actor owner")
        return EX_OK

    if sub == "list":
        base = proposals_dir(root)
        if not os.path.isdir(base):
            print(c_dim("(belum ada proposal dream)"))
            return EX_OK
        rows = []
        for name in sorted(os.listdir(base)):
            mf = os.path.join(base, name, "manifest.json")
            if not os.path.isfile(mf):
                continue
            try:
                m = json.load(open(mf, encoding="utf-8"))
            except Exception:
                continue
            status = "PENDING"
            for e in reversed(read_entries(root, "journal", kind="dreams", strict=False)):
                if e.get("project") == name and e.get("kind") in ("dream-promote", "dream-reject"):
                    status = "PROMOTED" if e["kind"] == "dream-promote" else "REJECTED"
                    break
            rows.append([name, (m.get("ts") or "")[5:16], m.get("actor", "?"),
                         f"{m.get('counts', {}).get('ledger_events', 0)} ev",
                         status])
        if not rows:
            print(c_dim("(belum ada proposal dream)"))
            return EX_OK
        print(_fmt_table(["proposal", "dibuat", "oleh", "sinyal", "status"], rows))
        return EX_OK

    if sub == "review":
        pid = args.proposal
        if pid == "latest":
            pid = _latest_proposal(root)
            if not pid:
                print(c_red("belum ada proposal."), file=sys.stderr)
                return EX_ERR
        d = os.path.join(proposals_dir(root), pid)
        if not os.path.isdir(d):
            print(c_red(f"proposal {pid} tidak ditemukan di {proposals_dir(root)}"),
                  file=sys.stderr)
            return EX_ERR
        m = json.load(open(os.path.join(d, "manifest.json"), encoding="utf-8"))
        print(c_bld(f"Proposal: {pid}  (oleh {m.get('actor')}, {m.get('ts')})"))
        print(f"  {d}/")
        for name in m.get("files", []):
            p = os.path.join(d, name)
            n = len(_read_lines(p)) if os.path.exists(p) else 0
            print(f"  - {name:<20} {n} baris")
        print("")
        print(c_dim("(isi lengkap: buka folder proposal, atau promote kalau sudah layak.)"))
        return EX_OK

    if sub == "promote":
        try:
            require_owner(cfg, actor)
        except Rejected as r:
            append_entry(root, "journal", "dreams", {
                "kind": "dream-promote-denied", "project": args.proposal or "",
                "actor": actor, "cwd": os.getcwd(), "note": "; ".join(m for _, m in r.reasons),
            }, actor=actor)
            _print_reject(r.reasons, "dreams", args.proposal or "latest")
            return EX_REJECT
        pid = args.proposal
        if pid == "latest":
            pid = _latest_proposal(root)
        if not pid or not os.path.isdir(os.path.join(proposals_dir(root), pid)):
            print(c_red("proposal tidak ditemukan."), file=sys.stderr)
            return EX_ERR
        d = os.path.join(proposals_dir(root), pid)
        m = json.load(open(os.path.join(d, "manifest.json"), encoding="utf-8"))
        dst = memory_dir(root)
        tmp = dst + ".tmp-" + pid
        shutil.rmtree(tmp, ignore_errors=True)
        os.makedirs(tmp, exist_ok=True)
        for name in m.get("files", []):
            src = os.path.join(d, name)
            if os.path.isfile(src):
                shutil.copy2(src, os.path.join(tmp, name))
        with open(os.path.join(tmp, ".last-proposal"), "w", encoding="utf-8") as f:
            f.write(pid + "\n" + m.get("ts", "") + "\n")
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        old = dst + ".old-" + pid
        shutil.rmtree(old, ignore_errors=True)
        if os.path.isdir(dst):
            os.rename(dst, old)
        try:
            os.rename(tmp, dst)
        except Exception:
            if os.path.isdir(old):
                os.rename(old, dst)
            raise
        shutil.rmtree(old, ignore_errors=True)
        append_entry(root, "journal", "dreams", {
            "kind": "dream-promote", "project": pid, "actor": actor,
            "note": f"promote proposal {pid} → .workflow/memory/",
        }, actor=actor)
        print(c_grn(f"DIPROMOSIKAN {pid} oleh {actor} → {dst}"))
        print(c_dim("  Ledger tidak berubah. Git menyimpan versi memori lama."))
        maybe_commit(root, f"dream promote {pid}")
        return EX_OK

    if sub == "reject":
        try:
            require_owner(cfg, actor)
        except Rejected as r:
            _print_reject(r.reasons, "dreams", args.proposal)
            return EX_REJECT
        pid = args.proposal
        if pid == "latest":
            pid = _latest_proposal(root)
        d = os.path.join(proposals_dir(root), pid) if pid else None
        if not pid or not os.path.isdir(d):
            print(c_red("proposal tidak ditemukan."), file=sys.stderr)
            return EX_ERR
        reason = (args.reason or "").strip()
        if len(reason) < 3:
            print(c_red("dream reject butuh --reason (kenapa proposal ditolak)."),
                  file=sys.stderr)
            return EX_REJECT
        with open(os.path.join(d, "DECISION.md"), "w", encoding="utf-8") as f:
            f.write(f"# Keputusan: REJECT\n\nditandai {_now_str()} oleh {actor}.\n\n{reason}\n")
        append_entry(root, "journal", "dreams", {
            "kind": "dream-reject", "project": pid, "actor": actor, "note": reason,
        }, actor=actor)
        print(c_yel(f"REJECTED {pid} oleh {actor}: {reason}"))
        maybe_commit(root, f"dream reject {pid}")
        return EX_OK

    if sub == "index":
        p = os.path.join(memory_dir(root), "INDEX.md")
        if not os.path.isfile(p):
            print(c_dim("(belum ada memori terpromosikan — jalankan "
                        "'workflow dream run' lalu 'workflow dream promote latest'.)"))
            return EX_OK
        print(f"# memori aktif: {p}")
        print("")
        print(open(p, encoding="utf-8").read())
        return EX_OK

    if sub == "journal":
        entries = read_entries(root, "journal", kind="dreams", strict=False)
        if args.last:
            entries = entries[-args.last:]
        if not entries:
            print(c_dim("(journal dream masih kosong)"))
            return EX_OK
        for e in entries:
            print(f"  #{e['seq']:<4} {e.get('ts', '')[:19]}  {e.get('kind'):<14} "
                  f"{e.get('project', '')}  oleh {e.get('actor', '')}"
                  + (f"  — {e.get('note')}" if e.get("note") else ""))
        return EX_OK

    if sub == "clear":
        try:
            require_owner(cfg, actor)
        except Rejected as r:
            _print_reject(r.reasons, "dreams", "all")
            return EX_REJECT
        if not args.yes:
            print(c_red("konfirmasi: dream clear --yes (hapus proposal & memori; "
                        "journal tetap tersimpan)."), file=sys.stderr)
            return EX_REJECT
        for d in (proposals_dir(root), memory_dir(root)):
            shutil.rmtree(d, ignore_errors=True)
        print(c_grn("OK. Proposal & memori dibersihkan (journal dream tetap ada)."))
        maybe_commit(root, "dream clear")
        return EX_OK

    print("sub-perintah dream tidak dikenal:", sub, file=sys.stderr)
    return EX_ERR


def _latest_proposal(root):
    base = proposals_dir(root)
    if not os.path.isdir(base):
        return None
    dirs = [n for n in os.listdir(base)
            if os.path.isfile(os.path.join(base, n, "manifest.json"))]
    if not dirs:
        return None
    return max(dirs, key=lambda n: os.path.getmtime(os.path.join(base, n)))


# ----------------------------------------------------------------------------
# BOARD — view turunan
# ----------------------------------------------------------------------------

def generate_board(root, cfg):
    status_order = cfg["states"]
    lines = []
    now = _ts()
    label = cfg.get("root_label", "NEVGO")

    lines.append(f"# BOARD {label} — ringkasan gabungan seluruh divisi")
    lines.append("")
    lines.append(f"> View turunan. Dibangun otomatis dari ledger oleh `workflow board --write` pada {now}.")
    lines.append(f"> Jangan diedit manual — akan tertimpa. Ledger di `.workflow/ledger/` adalah sumber kebenaran.")
    lines.append("")
    lines.append(f"**State machine:** {' → '.join(cfg['states'])}  ")
    lines.append("")
    lines.append("_(status murni = tahap pekerjaan. Kondisi seperti 'selesai tapi perlu dicek lagi' ditulis "
                 "sebagai catatan bebas lewat `workflow note`, bukan status.)_")
    lines.append("")

    # statistik ringkas
    counts = {s: 0 for s in status_order}
    per_div = {}
    all_recent = []
    notes_recent = []
    for div in cfg["divisions"]:
        entries = read_entries(root, div, strict=False)
        states = compute_states(entries)
        per_div[div] = states
        for proj in _all_project_names(entries):
            s = states.get(proj, {}).get("state") or "IDE"
            counts[s] = counts.get(s, 0) + 1
        for e in entries:
            if e.get("kind") in ("submit", "reopen", "override"):
                all_recent.append(e)
            if e.get("kind") == "note":
                notes_recent.append(e)

    lines.append("## Ringkasan status")
    lines.append("")
    if sum(counts.values()):
        lines.append("  " + " · ".join(f"{s}: {counts.get(s, 0)}" for s in status_order))
    else:
        lines.append(c_dim("  (belum ada aktivitas)"))

    # per divisi
    for div in cfg["divisions"]:
        lab = cfg["divisions"][div]["label"]
        entries = read_entries(root, div, strict=False)
        states = compute_states(entries)
        names = _all_project_names(entries)
        if not names:
            continue
        lines.append("")
        lines.append(f"## Divisi {lab} (`{div}`)")
        lines.append("")
        rows = []
        for proj in names:
            s = states.get(proj, {}).get("state") or "IDE"
            ev = ""
            cc_set = set()
            upd = ""
            for e in reversed(entries):
                if e.get("project") != proj:
                    continue
                if e.get("cc"):
                    for t in e["cc"]:
                        cc_set.add(t)
                if not upd:
                    upd = (e.get("ts") or "")[11:16]
                if not ev and e.get("kind") == "submit" and e.get("evidence"):
                    ev = _trunc(e["evidence"], 46)
            rows.append([
                s,
                proj,
                upd,
                ev or c_dim("—"),
                ("cc:" + ",".join(sorted(cc_set))) if cc_set else "",
            ])
        hdr = ["status", "proyek", "update", "evidence terakhir", "cc"]
        lines.append(_fmt_table(hdr, rows))
        lines.append("")

    # dependency terbuka
    open_edges = all_open_edges(root, cfg)
    if open_edges:
        lines.append("## Dependency terbuka (closing ditahan sampai selesai/direkonsiliasi)")
        lines.append("")
        rows = []
        for e in open_edges:
            fq, tq = counterpart(e)
            other_state = _qname_state(root, cfg, tq) or "IDE"
            dep_ok = "✓ terpenuhi" if other_state == "SELESAI" else c_red("✗ menunggu")
            rows.append([fq, "→ " + tq, dep_ok, _trunc(e.get("reason") or e.get("note"), 40)])
        lines.append(_fmt_table(["dependen", "ditunggu", "status", "alasan"], rows))
        lines.append("")
    else:
        lines.append("## Dependency")
        lines.append("")
        lines.append(c_dim("  (tidak ada dependency terbuka)"))
        lines.append("")

    # aktivitas terakhir
    all_recent.sort(key=lambda e: e.get("ts", ""), reverse=True)
    if all_recent:
        lines.append("## Aktivitas terakhir")
        lines.append("")
        rows = []
        for e in all_recent[:9]:
            rows.append([
                qname(e.get("div"), e.get("project")),
                e.get("kind", ""),
                f"{e.get('from') or 'IDE'}→{e.get('to') or ''}" if e.get("to") else "—",
                (e.get("ts") or "")[11:16],
                e.get("actor", ""),
            ])
        lines.append(_fmt_table(["proyek", "kind", "transisi", "jam", "aktor"], rows))
        lines.append("")

    # catatan bebas terbaru
    notes_recent.sort(key=lambda e: e.get("ts", ""), reverse=True)
    if notes_recent:
        lines.append("## Catatan bebas terbaru (bukan status)")
        lines.append("")
        for e in notes_recent[:6]:
            proj = qname(e.get("div"), e.get("project")) if e.get("project") else f"{e.get('div')}/—"
            lines.append(f"- **{proj}** ({e.get('actor')}, {(e.get('ts') or '')[:16]}): "
                         f"{_trunc(e.get('note') or e.get('message'), 120)}")
        lines.append("")

    # penolakan terbaru
    rejs = []
    for div in cfg["divisions"]:
        for e in read_entries(root, div, kind="rejections", strict=False):
            e = dict(e)
            rejs.append(e)
    rejs.sort(key=lambda e: e.get("ts", ""), reverse=True)
    lines.append("## Penolakan validator terbaru")
    lines.append("")
    if not rejs:
        lines.append(c_dim("  (belum ada penolakan tercatat)"))
    else:
        for e in rejs[:6]:
            proj = qname(e.get("div"), e.get("project")) if e.get("project") else e.get("div", "?")
            st = f" → {e.get('requested_status')}" if e.get("requested_status") else ""
            reasons = format_rejections(e)
            first = reasons[0] if reasons else ""
            lines.append(f"- **{proj}**{st} oleh {e.get('actor')} ({e.get('kind', 'reject')}): "
                         f"{_trunc(first, 100)}")
    # memori terkompilasi (dream) bila sudah dipromosikan
    mem_idx = os.path.join(memory_dir(root), "INDEX.md")
    if os.path.isfile(mem_idx):
        lines.append("## Memori terkompilasi (Dreaming)")
        lines.append("")
        lines.append("> Dipromosikan dari proposal `workflow dream` — baca sebelum mulai sesi "
                     "baru: `workflow dream index`.")
        lines.append("")
        for ln in _read_lines(mem_idx)[:6]:
            if ln.strip():
                lines.append(_trunc(ln, 118))
        lines.append("")

    lines.append("")
    lines.append(f"---")
    lines.append(f"_Dibuat {now}. Sumber: `.workflow/ledger/*.jsonl`. Periksa integritas: `workflow verify`._")
    return "\n".join(lines)


def write_board(root, cfg):
    os.makedirs(root, exist_ok=True)
    target = os.path.join(root, "BOARD.md")
    content = generate_board(root, cfg)
    d = os.path.dirname(target)
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".board-")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(content)
        os.replace(tmp, target)
    except BaseException:
        try:
            os.remove(tmp)
        except OSError:
            pass
        raise
    return target


# ----------------------------------------------------------------------------
# Penolakan -> journal (data terpisah, append-only)
# ----------------------------------------------------------------------------

def record_rejection(root, div, payload):
    try:
        append_entry(root, div, "rejections", payload)
        return True
    except WorkflowError:
        return False


# ----------------------------------------------------------------------------
# Helper argumen
# ----------------------------------------------------------------------------

def add_actor_arg(p):
    p.add_argument("--actor", default=None,
                   help="siapa yang mencatat (nama platform AI, atau 'owner'). "
                        "Default: $NEVGO_ACTOR, kalau kosong 'manual'.")


def resolve_actor(cfg, args):
    a = getattr(args, "actor", None) or os.environ.get("NEVGO_ACTOR") or "manual"
    return a


def require_owner(cfg, actor):
    if actor not in cfg["owner_actors"]:
        raise Rejected([("owner", f"operasi ini khusus owner (aktor '{actor}' tidak ada di "
                                  f"owner_actors={cfg['owner_actors']})")])


def read_text_file(p):
    with open(p, encoding="utf-8") as f:
        return f.read().strip()


def fill_text_args(args, field):
    """--evidence --evidence-file dst."""
    for k, filek in [("evidence", "evidence_file"), ("verification", "verification_file"),
                     ("note", "note_file"), ("reason", "reason_file")]:
        if getattr(args, filek, None):
            setattr(args, k, read_text_file(getattr(args, filek)))


def parse_cc_list(args):
    cc = list(getattr(args, "cc", []) or [])
    return cc


def check_cc(cfg, cc):
    ok = True
    for tok in cc:
        parts = tok.split(":", 1)
        if parts[0] not in cfg["divisions"]:
            print(c_red(f"  cc: divisi '{parts[0]}' tidak dikenal"), file=sys.stderr)
            ok = False
        elif len(parts) == 2 and not SLUG_RE.match(parts[1]):
            print(c_red(f"  cc: proyek '{parts[1]}' bukan slug valid (a-z, 0-9, '-')"), file=sys.stderr)
            ok = False
    return ok


def project_ctx(root, cfg, need_div=True, need_project=None):
    """Ambil divisi dari cwd (dan proyek dari args kalau ada)."""
    div = division_from_cwd(cfg, root)
    if need_div and not div:
        raise WorkflowError(
            "working directory ini tidak berada di dalam folder divisi mana pun.\n"
            "Divisi ditentukan dari FOLDER, bukan dari klaim di chat.\n"
            "Folder yang dikenal:\n" +
            "\n".join(f"  - {division_dir(root, cfg, d)}  ({cfg['divisions'][d]['label']})"
                      for d in cfg["divisions"]))
    return div


def git(*args, root, check=True):
    try:
        r = subprocess.run(["git", "-C", root] + list(args),
                           capture_output=True, text=True)
        if check and r.returncode != 0:
            raise WorkflowError(f"git {' '.join(args)} gagal:\n{r.stderr.strip()}")
        return r
    except FileNotFoundError:
        raise WorkflowError("git tidak terpasang di mesin ini")


def git_repo(root):
    return os.path.isdir(os.path.join(root, ".git"))


def maybe_commit(root, msg):
    if os.environ.get("NEVGO_NO_GIT"):
        return
    if not git_repo(root):
        return
    try:
        git("add", "-A", root=root)
        r = git("commit", "-m", msg, root=root, check=False)
        if r.returncode == 0:
            print(c_dim(f"  git: {r.stdout.strip()}"))
    except WorkflowError:
        pass


# ============================================================================
# Perintah-perintah CLI
# ============================================================================

def cmd_init(args):
    root = os.path.abspath(args.root)
    cfg_path = config_path(root)
    if os.path.exists(cfg_path) and not args.force:
        print(c_yel(f"Sudah ada konfigurasi di {root}. Pakai '--force' untuk isi yang hilang "
                    f"(tidak menghapus data)."))
        return EX_OK
    if os.path.exists(cfg_path):
        cfg = json.load(open(cfg_path, encoding="utf-8"))
    else:
        cfg = {"schema": 1, "root_label": "NEVGO",
               "owner_actors": DEFAULT_OWNER_ACTORS,
               "divisions": DEFAULT_DIVISIONS,
               "states": STATES_DEFAULT, "policy": DEFAULT_POLICY}
        os.makedirs(root, exist_ok=True)
        with open(cfg_path, "w", encoding="utf-8") as f:
            json.dump(cfg, f, ensure_ascii=False, indent=2)
            f.write("\n")
    for div, info in cfg["divisions"].items():
        d = os.path.join(root, info["dir"])
        os.makedirs(d, exist_ok=True)
        welcome = os.path.join(d, "WELCOME.md")
        if not os.path.exists(welcome):
            with open(welcome, "w", encoding="utf-8") as f:
                f.write(
                    f"# Divisi {info['label']} — folder kerja `{div}`\n\n"
                    "Agen/platform AI yang dipanggil dengan working directory di sini "
                    "dianggap bekerja di divisi ini — ditentukan oleh sistem, bukan klaim model.\n\n"
                    "Satu-satunya cara mencatat status:\n\n"
                    "    workflow submit --project <proyek> --status <STATUS> [--evidence ...]\n\n"
                    "Lihat `workflow states` dan `workflow whoami`.\n")
    for sub in ("ledger", "rejections"):
        os.makedirs(os.path.join(root, ".workflow", sub), exist_ok=True)
    # config git lokal supaya commit jalan tanpa konfigurasi global
    if not os.environ.get("NEVGO_NO_GIT") and not os.path.isdir(os.path.join(root, ".git")):
        git("init", "-b", "main", root=root, check=False)
        git("config", "user.name", "Nevgo Workflow", root=root, check=False)
        git("config", "user.email", "nevgo-workflow@local", root=root, check=False)
    if not os.environ.get("NEVGO_NO_GIT"):
        git("add", "-A", root=root, check=False)
        git("commit", "-m", "init nevgo workflow", root=root, check=False)
    print(c_grn(f"OK. Root: {root}"))
    print("  divisi     : " + ", ".join(cfg["divisions"]))
    print("  state      : " + " → ".join(cfg["states"]))
    print("  owner      : " + ", ".join(cfg["owner_actors"]))
    print("Jalankan 'workflow states' untuk aturan lengkap, 'workflow whoami' untuk cek divisi.")
    return EX_OK


def cmd_whoami(args):
    root = args.root
    cfg = load_config(root)
    div = division_from_cwd(cfg, root)
    print(f"root     : {root}")
    if div:
        print(f"divisi   : {div}  ({cfg['divisions'][div]['label']})")
        print(f"ledger   : {store_path(root, div, 'ledger')}")
        return EX_OK
    print(c_red("divisi   : (tidak ada — cwd di luar semua folder divisi)"))
    print("Masuk ke salah satu folder divisi:")
    for d in cfg["divisions"]:
        print(f"           - {division_dir(root, cfg, d)}")
    return EX_ERR


def cmd_states(args):
    root = args.root
    cfg = load_config(root)
    pol = cfg["policy"]
    print(c_bld("State machine (hanya 5 status; status murni = tahap pekerjaan):"))
    print("")
    print("   " + c_grn(" → ".join(cfg["states"])))
    print("")
    print(" - Tidak ada 'hampir selesai'. Kondisi seperti itu ditulis via `workflow note`.")
    print(" - Transisi ke SELESAI dikunci ketat:")
    for s in pol["selesai_min_from"]:
        pass
    print(f"     · harus datang dari: {', '.join(pol['selesai_min_from'])}")
    for s in pol["require_evidence_for"]:
        print(f"     · wajib --evidence (min {pol['evidence_min_len']} karakter)")
    for s in pol["require_verification_for"]:
        print(f"     · wajib --verification (min {pol['verification_min_len']} karakter)")
    print("     · closing proyek ditahan selama ia punya dependensi keluar (X → Y)")
    print("       yang belum SELESAI — sampai owner rekonsiliasi / --override")
    print(" - Status lain longgar tapi tetap wajib lewat CLI ini (tercatat, append-only).")
    print(" - Submit status yang sama 2x = no-op (tidak ada duplikat).")
    print(" - Keluar dari SELESAI = `workflow reopen` (khusus owner).")
    print("")
    print(c_bld("Aturan kepemilikan:"))
    print(" - Divisi ditentukan dari working directory (bukan klaim di chat). Cek: `workflow whoami`.")
    print(" - Bantuan lintas divisi dicatat sebagai --cc, tidak memicu eksekusi apa pun.")
    print("")
    print(c_bld("Contoh:"))
    print('   workflow submit --project redesign-checkout --status SIAP-JALAN')
    print('   workflow submit --project redesign-checkout --status SELESAI \\')
    print('       --evidence "url live: checkout.nevgo.id, screenshot terlampir" \\')
    print('       --verification "curl -I checkout.nevgo.id -> 200 OK, dicek manual"')
    return EX_OK


def warn_crossdiv(root, cfg, div, project):
    """Kalau nama proyek ini sudah hidup di divisi lain, ingatkan — bisa jadi
    agen 'membantu' lalu mencatatnya sebagai kerjaan divisinya sendiri."""
    for d in cfg["divisions"]:
        if d == div:
            continue
        entries = read_entries(root, d, strict=False)
        st = compute_states(entries)
        if project in st:
            print(c_yel(
                f"  hati-hati: '{project}' sudah tercatat di divisi '{d}' "
                f"(status: {st[project]['state']}). Kamu menulis {div}/{project}.\n"
                f"  Kalau ini kerja lintas divisi, gunakan --cc {d}:{project} dan jangan "
                f"menutup proyek divisi lain."), file=sys.stderr)


def cmd_submit(args):
    root = args.root
    cfg = load_config(root)
    fill_text_args(args, None)
    div = project_ctx(root, cfg, need_div=True)
    actor = resolve_actor(cfg, args)
    if not SLUG_RE.match(args.project):
        print(c_red(f"DITOLAK: nama proyek '{args.project}' bukan slug valid "
                    f"(a-z, 0-9, '-', maks 80 char)."), file=sys.stderr)
        return EX_REJECT
    if not check_cc(cfg, args.cc):
        return EX_REJECT
    st_n = norm_state(args.status)
    if st_n not in cfg["states"]:
        print(c_red(f"DITOLAK: status '{args.status}' tidak dikenal. "
                    f"Status valid: {', '.join(cfg['states'])}"), file=sys.stderr)
        return EX_REJECT

    args.status = st_n
    if not args.override:
        warn_crossdiv(root, cfg, div, args.project)
    entries = read_entries(root, div)
    states = compute_states(entries)
    cur = states.get(args.project)
    current = (cur["state"] if cur else None, bool(cur))

    # duplicate = no-op
    if cur and cur["state"] == st_n:
        print(c_dim(f"no-op: '{qname(div, args.project)}' sudah dalam status {st_n}. "
                    f"Tidak ada yang ditulis (anti-duplikat)."))
        return EX_OK

    try:
        if args.override:
            require_owner(cfg, actor)
            if len((args.reason or "").strip()) < 3:
                raise Rejected([("format", "--override butuh --reason berisi alasan owner "
                                          "(rekonsiliasi dependency / pertimbangan lain))")])
    except Rejected as r:
        reasons = r.reasons
        record_rejection(root, div, {
            "kind": "override-denied", "project": args.project,
            "requested_status": st_n, "actor": actor, "reasons": reasons,
            "cwd": os.getcwd(),
        })
        _print_reject(reasons, div, args.project)
        return EX_REJECT

    dec = validate_submit(root, cfg, args, div, current)
    if dec.action == "noop":
        print(c_dim(f"no-op: sudah {st_n}. Tidak ada yang ditulis."))
        return EX_OK

    if dec.action in ("reject", "held"):
        payload = {
            "kind": "hold" if dec.held else "reject",
            "project": args.project,
            "requested_status": st_n,
            "actor": actor,
            "cwd": os.getcwd(),
            "reasons": [[t, m] for t, m in dec.reasons],
        }
        record_rejection(root, div, payload)
        _print_reject(dec.reasons, div, args.project)
        # Prioritas exit-code: alasan non-hold (validasi gagal) = REJECT;
        # kalau satu-satunya alasan memang hold dependency = HELD.
        only_hold = dec.held and all(t == "hold" for t, _ in dec.reasons)
        return EX_HELD if only_hold else EX_REJECT

    # --- tulis -------------------------------------------------------------
    rec = append_entry(root, div, "ledger", {
        "kind": "override" if args.override else "submit",
        "project": args.project,
        "from": dec.info["from"],
        "to": st_n,
        "evidence": (args.evidence or "").strip(),
        "verification": (args.verification or "").strip(),
        "note": (args.note or "").strip(),
        "cc": args.cc,
        "reason": (args.reason or "").strip() or None,
    }, actor=actor)
    print(c_grn(f"OK #{rec['seq']}  {qname(div, args.project)}  "
                f"{dec.info['from']} → {st_n}   (oleh {actor})"))
    if args.cc:
        print(c_dim(f"    cc: {', '.join(args.cc)} — dicatat, tidak memicu apa pun."))
    maybe_commit(root, f"{div}: {args.project} {dec.info['from']}→{st_n}")
    return EX_OK


def _print_reject(reasons, div, project):
    print(c_red(f"DITOLAK — tidak ada byte yang ditulis ke ledger {div}."), file=sys.stderr)
    for tag, msg in reasons:
        print(c_red(f"  ✗ [{tag}] {msg}"), file=sys.stderr)
    print("Penolakan ini dicatat di `.workflow/rejections/` sebagai data terpisah.", file=sys.stderr)


def cmd_note(args):
    root = args.root
    cfg = load_config(root)
    fill_text_args(args, None)
    div = project_ctx(root, cfg, need_div=True)
    actor = resolve_actor(cfg, args)
    msg = (args.message or args.note or "").strip()
    if len(msg) < 2:
        print(c_red("note butuh --message (catatan bebas, tidak mengubah status)."), file=sys.stderr)
        return EX_REJECT
    if args.project and not SLUG_RE.match(args.project):
        print(c_red(f"proyek '{args.project}' bukan slug valid."), file=sys.stderr)
        return EX_REJECT
    if not check_cc(cfg, args.cc):
        return EX_REJECT
    rec = append_entry(root, div, "ledger", {
        "kind": "note",
        "project": args.project or None,
        "note": msg,
        "evidence": (args.evidence or "").strip() or None,
        "cc": args.cc,
    }, actor=actor)
    print(c_grn(f"OK #{rec['seq']}  catatan @{div}"
                + (f"/{args.project}" if args.project else "")
                + f"  (oleh {actor})"))
    maybe_commit(root, f"{div}: catatan {args.project or ''}".strip())
    return EX_OK


def cmd_status(args):
    root = args.root
    cfg = load_config(root)
    div = args.division or division_from_cwd(cfg, root)
    divisions = [div] if div else list(cfg["divisions"])
    out = {}
    for d in divisions:
        entries = read_entries(root, d, strict=False)
        st = compute_states(entries)
        for proj in _all_project_names(entries):
            s = st.get(proj, {}).get("state") or "IDE"
            ts = st.get(proj, {}).get("ts", "")
            if args.project and args.project != proj:
                continue
            out.setdefault(d, {})[proj] = {"state": s, "ts": ts}
    if args.json:
        print(json.dumps(out, ensure_ascii=False, indent=2))
        return EX_OK
    anyrow = False
    for d in divisions:
        rows = []
        for proj, info in sorted(out.get(d, {}).items()):
            anyrow = True
            rows.append([info["state"], proj, (info["ts"] or "")[:16]])
        if rows or (not args.project and not div):
            lab = cfg["divisions"][d]["label"]
            print(c_bld(f"Divisi {lab} ({d})"))
            print(_fmt_table(["status", "proyek", "update"], rows))
            print("")
    if not anyrow:
        print(c_dim("(tidak ada proyek tercatat)"))
    return EX_OK


def cmd_log(args):
    root = args.root
    cfg = load_config(root)
    div = args.division or division_from_cwd(cfg, root)
    divisions = [div] if div else list(cfg["divisions"])
    n = args.last
    for d in divisions:
        entries = read_entries(root, d, strict=False)
        if args.project:
            entries = [e for e in entries if e.get("project") == args.project]
        if n:
            entries = entries[-n:]
        if not entries:
            continue
        lab = cfg["divisions"][d]["label"]
        print(c_bld(f"Ledger divisi {lab} ({d}) — {len(entries)} baris"))
        for e in entries:
            kind = e.get("kind", "?")
            proj = e.get("project") or "—"
            act = f"{e.get('from') or ''}→{e.get('to') or ''}" if e.get("to") else ""
            print(f"  #{e['seq']:<3} {e.get('ts','')[:19]}  {kind:<8} {proj:<28} "
                  f"{act:<18} {e.get('actor','')}")
            ev = (e.get("evidence") or "").strip()
            ve = (e.get("verification") or "").strip()
            if ev:
                print(c_dim(f"        evidence: {_trunc(ev, 110)}"))
            if ve:
                print(c_dim(f"        verifikasi: {_trunc(ve, 110)}"))
            note = (e.get("note") or e.get("message") or "").strip()
            if note:
                print(c_dim(f"        catatan: {_trunc(note, 110)}"))
            if e.get("cc"):
                print(c_dim(f"        cc: {', '.join(e['cc'])}"))
        print("")
    return EX_OK


def cmd_rejections(args):
    root = args.root
    cfg = load_config(root)
    div = args.division or division_from_cwd(cfg, root)
    divisions = [div] if div else list(cfg["divisions"])
    for d in divisions:
        entries = read_entries(root, d, kind="rejections", strict=False)
        if args.last:
            entries = entries[-args.last:]
        if not entries:
            continue
        print(c_bld(f"Journal penolakan — divisi {d} ({len(entries)} kejadian)"))
        for e in entries:
            kind = e.get("kind", "reject")
            proj = e.get("project") or "—"
            st = f" → {e.get('requested_status')}" if e.get("requested_status") else ""
            print(f"  #{e['seq']:<3} {e.get('ts','')[:19]}  {kind:<10} {proj}{st}  oleh {e.get('actor','')}")
            for r in format_rejections(e):
                print(c_dim(f"        - {_trunc(r, 110)}"))
        print("")
    return EX_OK


def _dep_target_valid(cfg, args):
    if args.depends_on is None:
        print(c_red("butuh --depends-on DIV/PROYEK atau PROYEK (divisi sama)."), file=sys.stderr)
        return None
    if "/" in args.depends_on:
        ddiv, dproj = args.depends_on.split("/", 1)
    else:
        ddiv, dproj = None, args.depends_on
    if ddiv and ddiv not in cfg["divisions"]:
        print(c_red(f"divisi '{ddiv}' tidak dikenal."), file=sys.stderr)
        return None
    if not SLUG_RE.match(dproj):
        print(c_red(f"proyek '{dproj}' bukan slug valid."), file=sys.stderr)
        return None
    return ddiv, dproj


def cmd_depend(args):
    root = args.root
    cfg = load_config(root)
    actor = resolve_actor(cfg, args)
    if args.action == "list":
        edges = all_open_edges(root, cfg)
        if not edges:
            print(c_dim("(tidak ada dependency terbuka)"))
            return EX_OK
        rows = []
        for e in edges:
            fq, tq = counterpart(e)
            ostate = _qname_state(root, cfg, tq) or "IDE"
            rows.append([fq, "→ " + tq, ostate, _trunc(e.get("reason") or "", 36),
                         e.get("actor", ""), (e.get("ts") or "")[:16]])
        print(_fmt_table(["dependen", "ditunggu", "status-kini", "alasan", "oleh", "dibuka"], rows))
        return EX_OK
    div = project_ctx(root, cfg, need_div=True)
    target = _dep_target_valid(cfg, args)
    if not target:
        return EX_REJECT
    ddiv, dproj = target
    ddiv = ddiv or div
    if ddiv == div and dproj == args.project:
        print(c_red("self-dependency tidak masuk akal."), file=sys.stderr)
        return EX_REJECT
    # lokasi edge: selalu tersimpan di ledger divisi si dependen (div)
    existing = None
    for e in read_entries(root, div, strict=False):
        if e.get("kind") in ("dep", "dep-remove") and e.get("project") == args.project \
           and e.get("dep_div") == ddiv and e.get("dep_project") == dproj:
            existing = e
    if args.action == "remove":
        try:
            require_owner(cfg, actor)
        except Rejected as r:
            record_rejection(root, div, {
                "kind": "dep-remove-denied", "project": args.project,
                "dep_div": ddiv, "dep_project": dproj,
                "actor": actor, "cwd": os.getcwd(), "reasons": r.reasons,
            })
            _print_reject(r.reasons, div, args.project)
            return EX_REJECT
        if not existing or existing.get("kind") != "dep":
            print(c_dim(f"no-op: tidak ada dependency {args.project} → {ddiv}/{dproj} yang terbuka."))
            return EX_OK
        reason = (args.reason or "").strip()
        if len(reason) < 3:
            print(c_red("depend remove butuh --reason (kenapa dependency ditutup)."), file=sys.stderr)
            return EX_REJECT
        rec = append_entry(root, div, "ledger", {
            "kind": "dep-remove",
            "project": args.project, "dep_div": ddiv, "dep_project": dproj,
            "reason": reason, "note": None,
        }, actor=actor)
        print(c_grn(f"OK #{rec['seq']} dependency ditutup: {args.project} → {ddiv}/{dproj}"))
        maybe_commit(root, f"{div}: tutup dep {args.project}")
        return EX_OK
    # add
    reason = (args.reason or "").strip()
    if len(reason) < 3:
        print(c_red("depend add butuh --reason (kenapa proyek ini bergantung)."), file=sys.stderr)
        return EX_REJECT
    if existing and existing.get("kind") == "dep":
        print(c_dim(f"no-op: dependency {args.project} → {ddiv}/{dproj} sudah tercatat "
                    f"(#{existing['seq']}, {existing['actor']})."))
        return EX_OK
    rec = append_entry(root, div, "ledger", {
        "kind": "dep",
        "project": args.project, "dep_div": ddiv, "dep_project": dproj,
        "reason": reason, "note": None,
    }, actor=actor)
    print(c_grn(f"OK #{rec['seq']} dependency dicatat: {args.project} → {ddiv}/{dproj}"))
    print(c_dim("    Mencatat ≠ mengeksekusi. Tidak ada yang dijalankan otomatis."))
    maybe_commit(root, f"{div}: dep {args.project} → {ddiv}/{dproj}")
    return EX_OK


def cmd_reopen(args):
    root = args.root
    cfg = load_config(root)
    div = project_ctx(root, cfg, need_div=True)
    actor = resolve_actor(cfg, args)
    try:
        require_owner(cfg, actor)
    except Rejected as r:
        record_rejection(root, div, {
            "kind": "reopen-denied", "project": args.project, "actor": actor,
            "cwd": os.getcwd(), "reasons": r.reasons,
        })
        _print_reject(r.reasons, div, args.project)
        return EX_REJECT
    entries = read_entries(root, div)
    cur = compute_states(entries).get(args.project)
    if not cur or cur["state"] != "SELESAI":
        print(c_dim(f"no-op: '{args.project}' tidak sedang SELESAI."))
        return EX_OK
    reason = (args.reason or "").strip()
    if len(reason) < 3:
        print(c_red("reopen butuh --reason (kenapa dibuka lagi dari SELESAI)."), file=sys.stderr)
        return EX_REJECT
    rec = append_entry(root, div, "ledger", {
        "kind": "reopen",
        "project": args.project,
        "from": "SELESAI", "to": "BERJALAN",
        "reason": reason,
        "note": None,
    }, actor=actor)
    print(c_grn(f"OK #{rec['seq']} {args.project} SELESAI → BERJALAN (dibuka ulang oleh owner)"))
    maybe_commit(root, f"{div}: reopen {args.project}")
    return EX_OK


def cmd_board(args):
    root = args.root
    cfg = load_config(root)
    if args.write:
        target = write_board(root, cfg)
        print(c_grn(f"BOARD ditulis: {target}"))
        print(c_dim("   (view turunan — jika dihapus, tinggal jalankan perintah ini lagi.)"))
        maybe_commit(root, "board update")
    else:
        print(generate_board(root, cfg))
    return EX_OK


def cmd_verify(args):
    root = args.root
    cfg = load_config(root)
    bad = 0
    checks = [("ledger", div) for div in cfg["divisions"]] \
             + [("rejections", div) for div in cfg["divisions"]] \
             + [("dreams", "journal")]
    for kind, div in checks:
        ok, msg = verify_store(root, div, kind, heal=False)
        p = store_path(root, div, kind)
        n = len(_read_lines(p))
        state = c_grn("ok") if ok else c_red("KORUP")
        print(f"  {kind:<10} {div:<10} {state}   ({n} baris)  {msg if not ok else ''}")
        if not ok:
            bad += 1
    print("")
    if bad:
        print(c_red(f"{bad} store bermasalah. Pemulihan: "
                    f"git -C <root> log --oneline / git checkout -- .workflow"))
        return EX_ERR
    print(c_grn("Semua store konsisten (hash-chain & head pointer cocok)."))
    return EX_OK


def cmd_commit(args):
    root = args.root
    if not git_repo(root):
        print(c_yel("belum ada repo git di root ini (dibuat saat `workflow init`)."))
        return EX_OK
    git("add", "-A", root=root)
    r = git("commit", "-m", args.message or "nevgo workflow sync", root=root, check=False)
    if r.returncode == 0:
        print(c_grn("commit:" + r.stdout.strip()))
    else:
        print(c_dim("(tidak ada perubahan untuk di-commit)"))
    return EX_OK


def cmd_wipe(args):
    root = args.root
    cfg = load_config(root)
    actor = resolve_actor(cfg, args)
    try:
        require_owner(cfg, actor)
    except Rejected as r:
        print(c_red("wipe khusus owner (--actor owner)."), file=sys.stderr)
        return EX_REJECT
    if not args.yes:
        print(c_red("konfirmasi: tambahkan --yes. Ini menghapus seluruh ledger, penolakan, "
                    "dan BOARD (struktur folder tetap)."), file=sys.stderr)
        return EX_REJECT
    for div in cfg["divisions"]:
        for kind in ("ledger", "rejections"):
            for p in (store_path(root, div, kind), head_path(root, div, kind)):
                if os.path.exists(p):
                    os.remove(p)
    for p in (store_path(root, "journal", "dreams"), head_path(root, "journal", "dreams")):
        if os.path.exists(p):
            os.remove(p)
    target = os.path.join(root, "BOARD.md")
    if os.path.exists(target):
        os.remove(target)
    shutil.rmtree(dreams_root(root), ignore_errors=True)
    maybe_commit(root, "wipe: mulai bersih")
    print(c_grn("OK. Ledger, BOARD, & memori dream dikosongkan. Struktur tetap. "
                "Mulai dari `workflow submit`."))
    return EX_OK


# ----------------------------------------------------------------------------
# parser
# ----------------------------------------------------------------------------

def build_parser():
    ap = argparse.ArgumentParser(
        prog="workflow",
        description="nevgo-workflow — satu jalur tulis, append-only, untuk semua divisi & platform AI.",
        formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--version", action="version", version=f"nevgo-workflow {VERSION}")
    ap.add_argument("--root", default=None, help="root nevgo (default: $NEVGO_HOME atau ~/nevgo)")
    sub = ap.add_subparsers(dest="cmd", required=True, metavar="PERINTAH")

    def R(help_):
        return argparse.ArgumentParser(add_help=False)

    p = sub.add_parser("init", help="buat struktur, config, folder divisi, git init")
    p.add_argument("--force", action="store_true", help="isi file yang hilang bila sudah ada")
    p.set_defaults(fn=cmd_init)

    p = sub.add_parser("whoami", help="divisi apa yang ditentukan oleh working directory ini")
    p.set_defaults(fn=cmd_whoami)

    p = sub.add_parser("states", help="tampilkan state machine & aturan")
    p.set_defaults(fn=cmd_states)

    p = sub.add_parser("submit", help="catat transisi status (jalur tulis utama)")
    p.add_argument("--project", required=True, help="slug proyek, mis. redesign-checkout")
    p.add_argument("--status", required=True, help=f"IDE | DISIAPKAN | SIAP-JALAN | BERJALAN | SELESAI")
    p.add_argument("--evidence", default=None, help="bukti konkret (url/screenshot/hasil test)")
    p.add_argument("--evidence-file", default=None, help="baca evidence dari file")
    p.add_argument("--verification", default=None, help="cara klaim diperiksa")
    p.add_argument("--verification-file", default=None)
    p.add_argument("--note", default=None, help="catatan bebas menyertai transisi")
    p.add_argument("--note-file", default=None)
    p.add_argument("--reason", default=None, help="alasan (wajib untuk --override)")
    p.add_argument("--reason-file", default=None)
    add_actor_arg(p)
    p.add_argument("--cc", action="append", default=[], metavar="DIV[:PROYEK]",
                   help="bantuan lintas divisi (dicatat saja; tak memicu apa pun). Bisa diulang.")
    p.add_argument("--override", action="store_true",
                   help="khusus owner: paksa SELESAI meski ada dependency terbuka (butuh --reason)")
    p.set_defaults(fn=cmd_submit)

    p = sub.add_parser("note", help="catatan bebas — tidak mengubah status")
    p.add_argument("--project", default=None, help="proyek (opsional)")
    p.add_argument("--message", default=None)
    p.add_argument("--note", default=None, help="alias --message")
    p.add_argument("--evidence", default=None)
    add_actor_arg(p)
    p.add_argument("--cc", action="append", default=[])
    p.set_defaults(fn=cmd_note)

    p = sub.add_parser("status", help="status terakhir semua proyek")
    p.add_argument("--division", default=None)
    p.add_argument("--project", default=None)
    p.add_argument("--json", action="store_true")
    p.set_defaults(fn=cmd_status)

    p = sub.add_parser("log", help="isi mentah ledger (append-only)")
    p.add_argument("--division", default=None)
    p.add_argument("--project", default=None)
    p.add_argument("--last", type=int, default=None)
    p.set_defaults(fn=cmd_log)

    p = sub.add_parser("rejections", help="journal penolakan validator (data terpisah)")
    p.add_argument("--division", default=None)
    p.add_argument("--last", type=int, default=None)
    p.set_defaults(fn=cmd_rejections)

    p = sub.add_parser("depend", help="kelola dependency antar proyek (menahan closing)")
    p.add_argument("action", choices=["add", "remove", "list"])
    p.add_argument("--project", default=None, help="slug proyek dependen (kecuali list)")
    p.add_argument("--depends-on", default=None, metavar="DIV/PROYEK|PROYEK",
                   help="apa yang ditunggu proyek ini")
    add_actor_arg(p)
    p.add_argument("--reason", default=None)
    p.set_defaults(fn=cmd_depend)

    p = sub.add_parser("reopen", help="khusus owner: buka lagi proyek dari SELESAI ke BERJALAN")
    p.add_argument("--project", required=True)
    add_actor_arg(p)
    p.add_argument("--reason", required=True)
    p.set_defaults(fn=cmd_reopen)

    p = sub.add_parser("board", help="tampilkan / bangun BOARD (view turunan)")
    p.add_argument("--write", action="store_true", help="tulis BOARD.md di root")
    p.set_defaults(fn=cmd_board)

    # ---- dream: konsolidasi sesi menjadi memori terkompilasi -----------------
    p = sub.add_parser("dream", help="konsolidasi pengalaman sesi (ledger/rejections) "
                                     "menjadi memori terkompilasi — pola Memory & Dreaming")
    dp = p.add_subparsers(dest="dream_cmd", required=True, metavar="SUB",
                          help="run | list | review | promote | reject | index | journal | clear")
    d = dp.add_parser("run", help="buat PROPOSAL memori dari sinyal terbaru "
                                  "(tidak mengubah ledger; butuh review owner)")
    d.add_argument("--since-hours", type=int, default=168,
                   help="jendela sinyal dalam jam (default 168 = 7 hari; 0 = semua)")
    add_actor_arg(d)
    d = dp.add_parser("list", help="daftar proposal dream + status")
    d = dp.add_parser("review", help="ringkas isi proposal")
    d.add_argument("proposal", nargs="?", default="latest")
    d = dp.add_parser("promote", help="khusus owner: promosikan proposal → memori aktif")
    add_actor_arg(d)
    d.add_argument("proposal", nargs="?", default="latest")
    d = dp.add_parser("reject", help="khusus owner: tolak proposal (butuh --reason)")
    add_actor_arg(d)
    d.add_argument("proposal", nargs="?", default="latest")
    d.add_argument("--reason", required=False)
    d = dp.add_parser("index", help="tampilkan INDEX memori aktif")
    d = dp.add_parser("journal", help="riwayat aktivitas dream (run/promote/reject)")
    d.add_argument("--last", type=int, default=None)
    d = dp.add_parser("clear", help="khusus owner: hapus proposal & memori (journal tetap)")
    add_actor_arg(d)
    d.add_argument("--yes", action="store_true")

    p = sub.add_parser("verify", help="cek integritas hash-chain semua store")
    p.set_defaults(fn=cmd_verify)

    p = sub.add_parser("commit", help="commit semua perubahan ke git (ledger, BOARD, ...)")
    p.add_argument("--message", default=None)
    p.set_defaults(fn=cmd_commit)

    p = sub.add_parser("wipe", help="khusus owner: mulai bersih (hapus ledger, rejections, BOARD)")
    add_actor_arg(p)
    p.add_argument("--yes", action="store_true")
    p.set_defaults(fn=cmd_wipe)

    return ap


def main(argv=None):
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        root = os.path.abspath(args.root) if getattr(args, "root", None) else resolve_root()
        args.root = root
        if args.cmd == "init":
            return cmd_init(args)
        if args.cmd == "dream":
            return cmd_dream(args)
        return args.fn(args)
    except IntegrityError as e:
        print(c_red(f"ERROR: {e}"), file=sys.stderr)
        return EX_ERR
    except Rejected as e:
        _print_reject(e.reasons, "?", "?")
        return EX_HELD if e.held else EX_REJECT
    except WorkflowError as e:
        print(c_red(f"ERROR: {e}"), file=sys.stderr)
        return EX_ERR
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    sys.exit(main())
