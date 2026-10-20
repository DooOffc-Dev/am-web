#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

# =========================
# WARNA
# =========================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
line(){ echo -e "${CYAN}----------------------------------------${NC}"; }
success(){ echo -e "${GREEN}[✔] $1${NC}"; }
error(){ echo -e "${RED}[✖] $1${NC}"; }
warn(){ echo -e "${YELLOW}[!] $1${NC}"; }
info(){ echo -e "${BLUE}[*] $1${NC}"; }

# =========================
# CEK DEPENDENCY
# =========================
for cmd in curl jq git; do
  command -v "$cmd" >/dev/null 2>&1 || {
    error "Butuh '$cmd'. Install dulu: pkg install $cmd"
    exit 1
  }
done

clear; line
echo -e "${CYAN}🚀 GitHub Smart Uploader (Safe Edition)${NC}"
line; echo ""

# =========================
# AUTO FIX TERMUX GIT
# =========================
git config --global --add safe.directory "$(pwd)" 2>/dev/null || true
git config --global init.defaultBranch main 2>/dev/null || true

# =========================
# KONFIRMASI HAPUS .git
# =========================
if [ -d ".git" ]; then
  warn "Folder .git lama terdeteksi di: $(pwd)"
  read -r -p "Hapus .git lama? (y/n): " del
  if [ "$del" = "y" ]; then
    rm -rf .git
    success ".git dibersihkan"
  else
    warn "Dibatalkan. Script keluar."
    exit 0
  fi
fi

# =========================
# TOKEN (max 3x percobaan)
# =========================
attempt=0
username=""
while [ $attempt -lt 3 ]; do
  read -r -p "🔑 Masukkan GitHub Token: " token
  [ -z "$token" ] && { error "Token kosong."; attempt=$((attempt+1)); continue; }

  info "Validasi token..."
  resp=$(curl -s -H "Authorization: token $token" https://api.github.com/user)
  username=$(echo "$resp" | jq -r '.login // empty')

  if [ -n "$username" ] && [ "$username" != "null" ]; then
    success "Login: $username"
    break
  fi
  error "Token salah / tidak punya akses."
  attempt=$((attempt+1))
done
[ -z "$username" ] && { error "Gagal validasi token setelah 3x."; exit 1; }
echo ""

# =========================
# REPO
# =========================
info "Mengambil repository..."
repos=$(curl -s -H "Authorization: token $token" \
  "https://api.github.com/user/repos?per_page=100" | jq -r '.[].name')

line; echo -e "${CYAN}📦 Pilih Repository${NC}"; line
echo -e "${YELLOW}[0]${NC} Buat Repository Baru"

i=1
declare -a repo_list=()
while IFS= read -r r; do
  [ -z "$r" ] && continue
  echo -e "${YELLOW}[$i]${NC} $r"
  repo_list[$i]="$r"
  i=$((i+1))
done <<< "$repos"

while true; do
  read -r -p "👉 Nomor: " pilih_repo
  if [ "$pilih_repo" = "0" ]; then
    read -r -p "Nama repo: " repo
    [ -z "$repo" ] && { warn "Nama repo kosong."; continue; }
    read -r -p "Private? (y/n): " p
    private=false; [ "$p" = "y" ] && private=true

    curl -s -X POST https://api.github.com/user/repos \
      -H "Authorization: token $token" \
      -d "{\"name\":\"$repo\",\"private\":$private}" >/dev/null

    success "Repo '$repo' dibuat"
    break
  else
    repo="${repo_list[$pilih_repo]:-}"
    [ -n "$repo" ] && { success "Repo: $repo"; break; } || warn "Salah pilih"
  fi
done
echo ""

# =========================
# BRANCH
# =========================
info "Mengambil branch..."
branches=$(curl -s -H "Authorization: token $token" \
  "https://api.github.com/repos/$username/$repo/branches" | jq -r '.[].name')

line; echo -e "${CYAN}🌿 Pilih Branch${NC}"; line
i=1
declare -a branch_list=()
while IFS= read -r b; do
  [ -z "$b" ] && continue
  echo -e "${YELLOW}[$i]${NC} $b"
  branch_list[$i]="$b"
  i=$((i+1))
done <<< "$branches"
echo -e "${YELLOW}[0]${NC} Default / Buat Baru (main)"

while true; do
  read -r -p "👉 Nomor: " pilih_branch
  if [ "$pilih_branch" = "0" ]; then
    read -r -p "Nama branch (kosong=main): " branch
    branch="${branch:-main}"
    break
  else
    branch="${branch_list[$pilih_branch]:-}"
    [ -n "$branch" ] && break || warn "Pilihan salah"
  fi
done
success "Branch: $branch"; echo ""

# =========================
# SETUP GIT
# =========================
info "Setup git..."
git init >/dev/null 2>&1
git checkout -b "$branch" >/dev/null 2>&1 || git checkout "$branch"
git config user.name "$username"
git config user.email "$username@users.noreply.github.com"
git add .

if git diff --cached --quiet; then
  warn "Tidak ada file → commit init kosong"
  git commit --allow-empty -m "Init" >/dev/null 2>&1
else
  git commit -m "Upload: $(date)" >/dev/null 2>&1 || git commit -m "Upload" >/dev/null 2>&1
  success "Commit OK"
fi

# Remote TANPA token (token tidak disimpan di .git/config)
git remote remove origin 2>/dev/null || true
git remote add origin "https://github.com/$username/$repo.git"

# =========================
# PUSH (token via header, tidak tersimpan)
# =========================
line; info "Push ke GitHub..."; line
if git -c http.extraheader="Authorization: token $token" \
       push -u origin "$branch"; then
  success "Upload selesai!"
else
  warn "Push normal gagal, coba force-with-lease..."
  git -c http.extraheader="Authorization: token $token" \
      push -u origin "$branch" --force-with-lease
  success "Upload selesai (forced)!"
fi

echo ""
echo -e "${CYAN}https://github.com/$username/$repo${NC}"
line