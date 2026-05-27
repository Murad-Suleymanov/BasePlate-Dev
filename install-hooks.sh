#!/bin/bash
# install-hooks.sh — install pre-commit hooks machine-wide for ALL git repos.
#
# Run ONCE per developer machine. After this:
#   - Every future `git clone` automatically gets the hook (via init.templateDir).
#   - Already-cloned repos pick it up via core.hooksPath.
#   - The hook only fires if a repo has .pre-commit-config.yaml; other repos are
#     untouched.
#
# Usage:
#   ./install-hooks.sh
#
# To verify after install:
#   cd <any repo with .pre-commit-config.yaml>
#   git commit  → pre-commit hooks run automatically
#
# To remove later:
#   git config --global --unset init.templateDir
#   git config --global --unset core.hooksPath
#   rm -rf ~/.git-template

set -euo pipefail

TEMPLATE_DIR="$HOME/.git-template"
HOOKS_DIR="$TEMPLATE_DIR/hooks"

# Detect OS — pip --user puts scripts in different places per platform.
UNAME_S=$(uname -s 2>/dev/null || echo Unknown)
case "$UNAME_S" in
  Linux*)                                  OS=linux   ;;
  Darwin*)                                 OS=macos   ;;
  MINGW*|MSYS*|CYGWIN*|Windows_NT|Windows*) OS=windows ;;
  *)                                       OS=unknown ;;
esac
echo "==> Detected OS: $OS ($UNAME_S)"

# Add per-OS pip --user script dirs to PATH so we find pre-commit after install.
add_user_scripts_to_path() {
  case "$OS" in
    linux)
      [ -d "$HOME/.local/bin" ] && export PATH="$HOME/.local/bin:$PATH"
      ;;
    macos)
      # Homebrew/python.org installs put user scripts under ~/Library/Python/<ver>/bin
      [ -d "$HOME/.local/bin" ] && export PATH="$HOME/.local/bin:$PATH"
      for d in "$HOME"/Library/Python/*/bin; do
        [ -d "$d" ] && export PATH="$d:$PATH"
      done
      ;;
    windows)
      # Windows pip --user → %APPDATA%\Python\Python<ver>\Scripts
      # winget packages → %LOCALAPPDATA%\Microsoft\WinGet\Packages\<id>\[windows-amd64]
      for win_env in "${APPDATA:-}" "${LOCALAPPDATA:-}"; do
        [ -z "$win_env" ] && continue
        if command -v cygpath >/dev/null 2>&1; then
          unix_env=$(cygpath -u "$win_env")
        else
          unix_env=$(echo "$win_env" | sed -e 's|\\|/|g' -e 's|^\([A-Za-z]\):|/\L\1|')
        fi
        for d in \
          "$unix_env"/Python/Python*/Scripts \
          "$unix_env"/Microsoft/WinGet/Packages/*/ \
          "$unix_env"/Microsoft/WinGet/Packages/*/windows-amd64; do
          [ -d "$d" ] && export PATH="$d:$PATH"
        done
      done
      ;;
  esac
}

# Make sure existing user-scripts dirs are reachable before we check for pre-commit.
add_user_scripts_to_path

echo "==> Installing pre-commit framework (if missing)..."
if ! command -v pre-commit >/dev/null 2>&1; then
  if command -v pip3 >/dev/null 2>&1; then
    pip3 install --user pre-commit
  elif command -v pip >/dev/null 2>&1; then
    pip install --user pre-commit
  else
    echo "ERROR: pip / pip3 not found. Install Python first (https://www.python.org/downloads/)." >&2
    exit 1
  fi
  # Re-scan after install — the scripts dir may have just been created.
  add_user_scripts_to_path
  if ! command -v pre-commit >/dev/null 2>&1; then
    echo "ERROR: pre-commit installed but not on PATH. Add the pip user scripts dir to your PATH and re-run." >&2
    exit 1
  fi
fi
echo "    pre-commit: $(pre-commit --version)"

# ─── Install downstream tools (yq, helm) used by BasePlate hooks ──────────────
# These are not pre-commit dependencies — they are invoked by the remote hook
# scripts. Installing them up-front avoids a confusing failure on the dev's first
# `git commit`. Each function is a no-op if the tool is already on PATH.

_to_unix_path() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -u "$1"
  else
    echo "$1" | sed -e 's|\\|/|g' -e 's|^\([A-Za-z]\):|/\L\1|'
  fi
}

# winget lives at %LOCALAPPDATA%\Microsoft\WindowsApps\winget.exe — a reparse point
# Git Bash cannot exec directly. cmd.exe resolves it via the Windows API.
_winget_available() {
  [ -n "${LOCALAPPDATA:-}" ] && \
    cmd.exe /c "\"%LOCALAPPDATA%\\Microsoft\\WindowsApps\\winget.exe\" --version" >/dev/null 2>&1
}

_winget_install() {
  cmd.exe /c "\"%LOCALAPPDATA%\\Microsoft\\WindowsApps\\winget.exe\" install --id $1 --silent --accept-source-agreements --accept-package-agreements" >/dev/null 2>&1
}

_download_binary() {
  local url="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$dest" || return 1
  elif command -v wget >/dev/null 2>&1; then
    wget -q "$url" -O "$dest" || return 1
  else
    echo "ERROR: neither curl nor wget available to download $url" >&2
    return 1
  fi
  chmod +x "$dest"
}

ensure_tool() {
  # Args: <tool-name> <winget-id> <brew-pkg> <linux-binary-url> <macos-binary-url>
  local name="$1" winget_id="$2" brew_pkg="$3" linux_url="$4" macos_url="$5"
  if command -v "$name" >/dev/null 2>&1; then
    echo "    $name: already installed"
    return 0
  fi
  echo "==> Installing $name (missing)..."
  case "$OS" in
    windows)
      if _winget_available; then
        _winget_install "$winget_id" || { echo "ERROR: winget failed to install $winget_id" >&2; return 1; }
      else
        echo "ERROR: winget not found. Install $name manually (https://winget.run/pkg/${winget_id})" >&2
        return 1
      fi
      ;;
    macos)
      if command -v brew >/dev/null 2>&1; then
        brew install "$brew_pkg" >/dev/null || return 1
      elif [ -n "$macos_url" ]; then
        _download_binary "$macos_url" "$HOME/.local/bin/$name" || return 1
      else
        echo "ERROR: brew not found. Install Homebrew first (https://brew.sh) or install $name manually." >&2
        return 1
      fi
      ;;
    linux)
      if [ -n "$linux_url" ]; then
        _download_binary "$linux_url" "$HOME/.local/bin/$name" || return 1
      else
        echo "ERROR: no automatic install for $name on Linux. Install manually." >&2
        return 1
      fi
      ;;
    *)
      echo "ERROR: unknown OS, cannot auto-install $name" >&2
      return 1
      ;;
  esac
  add_user_scripts_to_path
  command -v "$name" >/dev/null 2>&1 || {
    echo "WARNING: $name installed but not yet on PATH. Restart your shell or open a new terminal." >&2
  }
}

# yq — Mike Farah's Go-based YAML processor (NOT the Python one).
ensure_tool yq MikeFarah.yq yq \
  "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64" \
  "https://github.com/mikefarah/yq/releases/latest/download/yq_darwin_amd64"

# helm — Kubernetes package manager. Official install script handles Linux + macOS.
if ! command -v helm >/dev/null 2>&1; then
  case "$OS" in
    windows)
      ensure_tool helm Helm.Helm helm "" ""
      ;;
    macos|linux)
      echo "==> Installing helm (via official get-helm-3 script)..."
      if command -v curl >/dev/null 2>&1; then
        curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash >/dev/null \
          || echo "WARNING: helm install script failed — install manually (https://helm.sh/docs/intro/install/)." >&2
      else
        echo "WARNING: curl not found. Install helm manually (https://helm.sh/docs/intro/install/)." >&2
      fi
      ;;
  esac
else
  echo "    helm: already installed"
fi

echo "==> Setting up shared git hooks directory at $HOOKS_DIR..."
mkdir -p "$HOOKS_DIR"

# The hook script delegates to pre-commit framework when the repo has a config.
# Repos without .pre-commit-config.yaml pass through silently.
# The hook self-heals: if pre-commit isn't on PATH (common with GUI-launched git or
# terminals opened before PATH was updated), it searches common pip --user locations.
cat > "$HOOKS_DIR/pre-commit" <<'HOOK'
#!/bin/sh
# Shared pre-commit hook — installed machine-wide by BasePlate-Dev/install-hooks.sh.
# No-op for repos that don't use pre-commit.
if [ -f ".pre-commit-config.yaml" ]; then
  # Self-heal PATH: pre-commit itself + tools downstream hooks invoke (yq, helm, ...).
  # Stale terminals or fresh-clone shells often miss these; rather than ask devs to
  # reopen their shell, we scan the canonical install locations and prepend any
  # that exist. Safe no-op on Linux/macOS where the dirs don't exist.
  _add_to_path() { [ -d "$1" ] && PATH="$1:$PATH" && export PATH; }
  _to_unix() {
    if command -v cygpath >/dev/null 2>&1; then
      cygpath -u "$1"
    else
      echo "$1" | sed -e 's|\\|/|g' -e 's|^\([A-Za-z]\):|/\L\1|'
    fi
  }
  # pip --user installs (pre-commit itself lives here)
  _add_to_path "$HOME/.local/bin"
  for d in "$HOME"/Library/Python/*/bin; do _add_to_path "$d"; done
  # Windows: pip --user + winget package dirs (yq, helm, etc.)
  for win_env in "${APPDATA:-}" "${LOCALAPPDATA:-}"; do
    [ -z "$win_env" ] && continue
    unix_env=$(_to_unix "$win_env")
    for d in \
      "$unix_env"/Python/Python*/Scripts \
      "$unix_env"/Programs/Python/Python*/Scripts \
      "$unix_env"/Microsoft/WinGet/Packages/*/ \
      "$unix_env"/Microsoft/WinGet/Packages/*/windows-amd64; do
      _add_to_path "$d"
    done
  done
  exec pre-commit run --hook-stage commit
fi
HOOK
chmod +x "$HOOKS_DIR/pre-commit"

echo "==> Configuring git globally..."
# init.templateDir → future `git init` / `git clone` copies these hooks into the new repo's .git/hooks/
git config --global init.templateDir "$TEMPLATE_DIR"
# core.hooksPath → existing repos use the shared hooks immediately (no need to re-init)
git config --global core.hooksPath "$HOOKS_DIR"

echo
echo "✓ Done. Pre-commit hooks are now active machine-wide."
echo
echo "Verification:"
echo "  git config --global --get init.templateDir   → $(git config --global --get init.templateDir)"
echo "  git config --global --get core.hooksPath     → $(git config --global --get core.hooksPath)"
echo
echo "Next time you run \`git commit\` in BasePlate-Dev (or any repo with .pre-commit-config.yaml),"
echo "the configured hooks will run automatically. No manual \`pre-commit install\` per repo needed."
