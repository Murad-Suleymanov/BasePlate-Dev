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
  # pip --user installs to ~/.local/bin — ensure it's on PATH for this script
  export PATH="$HOME/.local/bin:$PATH"
  if ! command -v pre-commit >/dev/null 2>&1; then
    echo "ERROR: pre-commit installed but not on PATH. Add \$HOME/.local/bin to your PATH and re-run." >&2
    exit 1
  fi
fi
echo "    pre-commit: $(pre-commit --version)"

echo "==> Setting up shared git hooks directory at $HOOKS_DIR..."
mkdir -p "$HOOKS_DIR"

# The hook script delegates to pre-commit framework when the repo has a config.
# Repos without .pre-commit-config.yaml pass through silently.
cat > "$HOOKS_DIR/pre-commit" <<'HOOK'
#!/bin/sh
# Shared pre-commit hook — installed machine-wide by BasePlate-Dev/install-hooks.sh.
# No-op for repos that don't use pre-commit.
if [ -f ".pre-commit-config.yaml" ]; then
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
