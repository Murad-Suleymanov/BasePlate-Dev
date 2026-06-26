# BasePlate-Dev

Tenant values for BirService deployments. Each subfolder is one service; inside the folder:

- `service.yaml` — shared metadata for the service (`repo`, `owner`, optionally `image`/`tag`)
- `<env>.yaml` (e.g. `dev.yaml`, `prod.yaml`) — environment-specific config (single-instance or multi-instance shape)
- `routes.yaml` (optional) — base route catalog common to every cluster
- `routes-<env>.yaml` (optional) — per-cluster route overrides, layered on top of `routes.yaml`

**File-level inheritance.** Files are loaded base → override and deep-merged, so a child file only declares what differs:
`service.yaml` ⊕ `<env>.yaml` for config, and `routes.yaml` ⊕ `routes-<env>.yaml` for routes. Any of the layered files is optional.

## Validation — runs automatically, no manual steps

Every commit on a developer machine and every pull request runs the same validation hooks (semantic lint + Helm template render with JSON schema). You don't have to install or configure anything manually — one of the auto-triggers below fires depending on how you opened the repo:

| Scenario | What happens automatically |
|---|---|
| **You open this folder in VS Code** | A `folderOpen` task runs [install-hooks.sh](install-hooks.sh) silently. After a one-time confirmation prompt, hooks are active for every future commit. |
| **You use GitHub Codespaces or a Dev Container** | `.devcontainer/devcontainer.json` runs `install-hooks.sh` as `postCreateCommand`. Hooks active before you write a single line of code. |
| **You already ran `install-hooks.sh` once on this machine** | Machine-wide git config (`core.hooksPath`, `init.templateDir`) makes every existing and future repo with `.pre-commit-config.yaml` run hooks automatically. |
| **None of the above** | The PR you open runs the same hooks via [validate.yml](.github/workflows/validate.yml) on GitHub Actions. Branch protection rules block merging if validation fails. CI is the always-on safety net. |

Bottom line: **you cannot push broken values to `main`**. Local feedback is fast when you opt in via any of the auto-triggers above; otherwise CI catches it before merge.

## What the hooks check

- **`birservice-lint`** — semantic cross-field rules: singleton + HPA, image vs repo, limits < requests, multi-instance per-instance checks, `service.yaml` requires `owner`, …
- **`birservice-helm-validate`** — renders the chart with your `service.yaml` + `<env>.yaml` and the JSON schema. Catches typos, type mismatches, unknown fields, template errors.

## Working with values

### Single-instance (default)

```yaml
# hello-csharp/dev.yaml
hpa:
  minReplicas: 1
  maxReplicas: 3
resources:
  requests: {memory: 200Mi, cpu: 100m}
  limits:   {memory: 250Mi, cpu: 150m}
```

→ 1 BirService named `hello-csharp`, 1 Service `hello-csharp-svc`.

### Multi-instance

```yaml
# hello-csharp/prod.yaml
main:
  hpa: {minReplicas: 1, maxReplicas: 2}
  resources: ...
  traffic: ...
slave:
  inheritFrom: main      # copy main's whole config…
  hpa: {maxReplicas: 4}  # …override only this leaf (deep merge)
```

→ 2 BirServices `hello-csharp-main` + `hello-csharp-slave`, 2 Services. Shared service-level fields (`repo`, `owner`) inherited from `service.yaml`.

Use `inheritFrom: <instance>` to avoid duplicating a near-identical instance: it copies the named sibling's full config and lets you override just the fields you declare. The target must be a sibling in the same file and must not itself use `inheritFrom` (no chains). Omit it and each instance is fully independent, as before.

### One hostname for several instances

By default each instance gets its own DNS name. To route two instances through **one** hostname, a child joins the parent's route with `route.shareWith` + `route.pathPrefix`:

```yaml
# hello-csharp/prod.yaml
main:
  hpa: {minReplicas: 1, maxReplicas: 2}
  resources: ...
  traffic: ...
testing:
  inheritFrom: main
  route:
    shareWith: main        # use main's host (hello-csharp-main-<env>)
    pathPrefix: /testing   # only /testing → testing; everything else → main
```

→ one HTTPRoute on `hello-csharp-main-<env>`: `/testing` → `hello-csharp-testing-svc`, `/` → `hello-csharp-main-svc`. The child has no route of its own. Omit `pathPrefix` and set `weight: <0-100>` instead for a blue/green percentage split. The parent must not itself use `route.shareWith`, and a child must not set its own `hostname`.

### Route catalog with a shared base

Route policies (timeout, retries, …) live in a `_routes` map. Put what's common to
every cluster in `routes.yaml`; let each `routes-<env>.yaml` override only the leaves
that differ or add cluster-only routes. The files deep-merge, env on top of base:

```yaml
# hello-csharp/routes.yaml          (base — all clusters)
_routes:
  main:
    timeout: 30s

# hello-csharp/routes-prod.yaml     (prod override)
_routes:
  main:
    timeout: 15s          # tighter than the 30s base
  main-long-timeout:      # prod-only route, not in the base
    timeout: 120s

# hello-csharp/routes-dev.yaml      (dev override)
_routes: {}               # main inherits 30s unchanged — nothing to override
```

→ prod sees `main` (15s) + `main-long-timeout` (120s); dev sees `main` (30s). The base
and the env file are both optional, so an app can ship only `routes-<env>.yaml` (no
base) or only `routes.yaml` (identical on every cluster).

See [BasePlate/docs/user-guide/yaml-reference.md](https://github.com/Murad-Suleymanov/BasePlate/blob/main/docs/user-guide/yaml-reference.md) for the full field reference.

## Bypassing hooks (rarely needed)

```bash
git commit --no-verify -m "..."
```

This skips local hooks but the PR will still run the same validation in CI — you cannot bypass it for merging.

## Removing hooks from your machine

```bash
git config --global --unset init.templateDir
git config --global --unset core.hooksPath
rm -rf ~/.git-template
```

## Troubleshooting

**Hook says `pre-commit: command not found` when you commit?**
Add `~/.local/bin` to your `PATH` (where `pip install --user` placed the binary):

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

**VS Code shows a security prompt the first time you open the folder?**
That's expected — VS Code asks before running the auto-install task. Click "Allow" and it won't ask again on this machine.
