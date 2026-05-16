# BasePlate-Dev

Tenant catalog for [BasePlate](https://github.com/Murad-Suleymanov/BasePlate). Each subdirectory is one service; each `.yaml` file inside is one environment (filename = Kubernetes namespace).

```
BasePlate-Dev/
├── hello-csharp/
│   ├── dev.yaml      → namespace "dev"
│   └── prod.yaml     → namespace "prod"
├── hello-python/
│   ├── dev.yaml
│   └── prod.yaml
└── hello-websocket/
    └── prod.yaml
```

ArgoCD `ApplicationSet` watches the `*/dev.yaml` / `*/prod.yaml` pattern and renders each through the `birservice` Helm chart from BasePlate.

## Workspace Layout

For local validation to work, clone BasePlate as a sibling folder:

```
<workspace-root>/
├── BasePlate/                 # operator + chart + schema
└── BasePlate-Dev/             # this repo
```

Open the parent folder in VSCode (or add both repos to a single workspace). The `.vscode/settings.json` here points at `../BasePlate/charts/birservice/values.schema.json` — relative paths assume that layout.

If you only clone BasePlate-Dev, switch the schema reference in `.vscode/settings.json` to the GitHub raw URL (the file has the URL commented out).

## Validation

Four layers, fastest first. See [BasePlate docs/user-guide/validation.md](https://github.com/Murad-Suleymanov/BasePlate/blob/main/docs/user-guide/validation.md) for the full architecture.

### Layer 1 — IDE (real-time)

Already wired via `.vscode/settings.json`. As you type, VSCode underlines unknown fields, wrong types, and out-of-range values. `Ctrl+Space` autocompletes valid fields.

### Layer 2 — Pre-commit (before push)

One-time setup per clone:

```bash
pip install pre-commit
pre-commit install
```

After that, every `git commit` runs the same hooks CI runs:

- `birservice-helm-validate` — renders the chart with your values (schema + template check).
- `birservice-lint` — semantic cross-field rules (singleton+HPA, image+repo, limits<requests, …).

Helm and `yq` must be installed locally for the hooks to work:

```bash
# Helm (Windows)
winget install Helm.Helm
# Helm (Mac)
brew install helm
# yq (Mac/Linux)
brew install yq
```

To skip a single commit (CI still enforces):

```bash
SKIP=birservice-helm-validate git commit -m "..."
git commit --no-verify -m "..."         # skip all hooks
```

### Layer 3 — PR CI

`.github/workflows/validate.yml` runs `pre-commit` on every PR and push to `main`. Errors appear as:

- **Sticky PR comment** — formatted error list at the top of the conversation.
- **Inline annotations** — on the offending line in the diff view.

The `main` branch is protected: PR review + green `validate` check required for merge. Direct commits to `main` (including via the GitHub web editor) are blocked.

## Schema Reference

The single source of truth for valid fields, types, and ranges:

- Chart-level (Helm + IDE + pre-commit): [`BasePlate/charts/birservice/values.schema.json`](https://github.com/Murad-Suleymanov/BasePlate/blob/main/charts/birservice/values.schema.json)
- Developer-facing prose: [`BasePlate/docs/user-guide/yaml-reference.md`](https://github.com/Murad-Suleymanov/BasePlate/blob/main/docs/user-guide/yaml-reference.md)

## Adding a New Service

1. Create a folder named after the service: `mkdir my-app`
2. Add `dev.yaml` (and optionally `prod.yaml`) inside:
   ```yaml
   repo: https://github.com/your-org/my-app
   ```
3. Commit + push. ArgoCD picks it up within ~30 seconds.

The folder name becomes the BirService name. The filename (without `.yaml`) becomes the namespace.

## Common Patterns

```yaml
# Pre-built image, minimal
image: ealen/echo-server:0.9.2

# Build from GitHub
repo: https://github.com/your-org/api
tag: v1.2.0

# Autoscaling
repo: https://github.com/your-org/api
hpa: { minReplicas: 2, maxReplicas: 10 }

# Service mesh + outlier detection (default) + rate limit
repo: https://github.com/your-org/api
traffic:
  rateLimit: { enabled: true, mode: local, local: { requestsPerSecond: 100, burst: 20 } }

# Singleton worker (leader-elected, in-memory state)
repo: https://github.com/your-org/worker
singleton: true
replicas: 1

# Latency-critical with stricter PDB
repo: https://github.com/your-org/payments
hpa: { minReplicas: 4, maxReplicas: 20 }
maxDown: 1
traffic:
  latencyAware: true

# Canary rollout (10% on v2.0.0-rc1)
repo: https://github.com/your-org/api
canary: { enabled: true, weight: 10, tag: v2.0.0-rc1 }
```

More examples and full field descriptions in [yaml-reference.md](https://github.com/Murad-Suleymanov/BasePlate/blob/main/docs/user-guide/yaml-reference.md).
