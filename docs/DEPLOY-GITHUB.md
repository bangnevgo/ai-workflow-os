# Deploy ke GitHub

Cara mem-push prototipe `nevgo-workflow` (folder `~/nevgo`) ke GitHub.

> **Status repo lokal:** sudah `git init` (branch `main`, riwayat bersih),
> dan data demo ikut ter-commit (ledger `.workflow/`, memori dream, `BOARD.md`).
> Keputusan saat deploy ini: **public** + **sertakan data demo** — sesuai
> pilihan. Kalau suatu saat mau repo privat / tanpa data, langkahnya ada di
> bagian "Varian" di bawah.

## 1. Buat repo di github.com (sekali saja)

1. Buka **https://github.com/new**
2. **Repository name:** `ai-workflow-ledger`
   *(nama umum & generik; alternatif: `multi-agent-workflow`, `agent-workflow-ledger`)*
3. Pilih **Public**
4. **Jangan centang** "Add a README / .gitignore / license" — repo harus kosong
   supaya push bersih tanpa konflik.
5. Klik **Create repository**.

Repo kosong itu akan menampilkan instruksi "…or push an existing repository
from the command line" — pakai skrip di langkah 3, bukan instruksi itu apa adanya.

## 2. Siapkan autentikasi (pilih salah satu)

**Opsi A — `gh` CLI (paling nyaman, tanpa token manual):**
```bash
# di mesin Anda:
brew install gh            # macOS — atau cara instal sesuai OS
gh auth login              # ikuti wizard (HTTPS + browser)
```

**Opsi B — Personal Access Token** (bisa dipakai tanpa `gh`):
1. github.com → Settings → **Developer settings → Personal access tokens →
   Fine-grained tokens → Generate new token**
2. Repository access: **Only select repositories** → pilih `ai-workflow-ledger`
3. Permissions → **Contents: Read and write**
4. Salin token (format `github_pat_…`). Token ini *hanya* untuk sekali push —
   langsung cabut/expire setelah selesai.

## 3. Push

```bash
cd ~/nevgo

# --- kalau pakai gh CLI ---
./tools/github_deploy.sh --gh ai-workflow-ledger

# --- kalau pakai token ---
GITHUB_TOKEN=github_pat_xxx ./tools/github_deploy.sh https://github.com/<USERNAME>/ai-workflow-ledger.git
```

Skrip akan: cek working tree bersih → tambah remote `origin` (URL bersih,
token TIDAK tersimpan di `.git/config`) → push `main`. Kalau repo sudah Anda
buat dan Anda cuma mau push, mode dengan URL di atas adalah jalur utamanya.

### Verifikasi
```bash
git remote -v                       # URL tanpa token
git log origin/main --oneline | head
```
Buka repo di browser → file `README.md` tampil sebagai landing page.

## Varian & perawatan

- **Update berikutnya:** setelah kerja di `~/nevgo` (submit/dream/board),
  `./workflow commit` lalu `git push`.
- **Ingin privat tapi repo sudah public:** ubah di Settings → General →
  Danger Zone → Change visibility.
- **Tidak ingin data demo ter-push:** sebelum push pertama, jalankan
  `./workflow wipe --yes --actor owner`, lalu tambahkan ke `.gitignore`:
  ```
  .workflow/
  BOARD.md
  ```
  (struktur folder divisi & kode tetap ter-push, data di-bersihkan.)
- **Clone di mesin lain:** `git clone <url> ~/nevgo` — CLI `workflow` ikut
  terbawa, tinggal jalankan dari folder mana pun (root dideteksi dari
  `NEVGO_HOME` atau `~/nevgo`).
- **Menjaga sejarah tetap ringkas:** kalau riwayat mulai penuh commit kecil,
  sekali-sekali `git push --force-with-lease` setelah squash (lihat bagian
  cara squash di riwayat proyek).

## Troubleshooting

| Gejala | Penyebab & solusi |
|---|---|
| `push gagal … 403` | Token tidak punya akses ke repo itu → cek *Repository access* & scope *Contents: R/W* pada fine-grained token. |
| `remote: Repository not found` | Nama repo/username salah, atau repo belum dibuat. Cek URL. |
| `! [rejected] … fetch first` | Repo GitHub tidak kosong (ketambah README saat create) → biarkan, lalu: `git pull origin main --rebase` dan push ulang; atau hapus isi repo (Settings → Danger Zone → Delete this repository) dan buat lagi tanpa centang README. |
| Skrip bilang working tree kotor | Jalankan `./workflow commit` dulu, atau commit manual: `git add -A && git commit -m "..."`. |
