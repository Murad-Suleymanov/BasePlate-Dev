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
      if [ -n "${APPDATA:-}" ]; then
        if command -v cygpath >/dev/null 2>&1; then
          APPDATA_BASH=$(cygpath -u "$APPDATA")
        else
          APPDATA_BASH=$(echo "$APPDATA" | sed -e 's|\\|/|g' -e 's|^\([A-Za-z]\):|/\L\1|')
        fi
        for d in "$APPDATA_BASH"/Python/Python*/Scripts; do
          [ -d "$d" ] && export PATH="$d:$PATH"
        done
      fi
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
  if ! command -v pre-commit >/dev/null 2>&1; then
    # Self-heal: scan pip --user script dirs in case PATH wasn't refreshed.
    _add_to_path() { [ -d "$1" ] && PATH="$1:$PATH" && export PATH; }
    _add_to_path "$HOME/.local/bin"
    for d in "$HOME"/Library/Python/*/bin; do _add_to_path "$d"; done
    # Windows: $APPDATA / $LOCALAPPDATA use backslashes — convert for bash glob.
    for win_env in "${APPDATA:-}" "${LOCALAPPDATA:-}"; do
      [ -z "$win_env" ] && continue
      if command -v cygpath >/dev/null 2>&1; then
        unix_env=$(cygpath -u "$win_env")
      else
        unix_env=$(echo "$win_env" | sed -e 's|\\|/|g' -e 's|^\([A-Za-z]\):|/\L\1|')
      fi
      for d in "$unix_env"/Python/Python*/Scripts "$unix_env"/Programs/Python/Python*/Scripts; do
        _add_to_path "$d"
      done
    done
  fi
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
