# BasePlate-Dev

Tenant values for BirService deployments. Each subfolder is one service; inside the folder:

- `service.yaml` — shared metadata for the service (`repo`, `owner`, optionally `image`/`tag`)
- `<env>.yaml` (e.g. `dev.yaml`, `prod.yaml`) — environment-specific config (single-instance or multi-instance shape)

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
  hpa: {minReplicas: 1, maxReplicas: 2}
  resources: ...
  traffic: ...
```

→ 2 BirServices `hello-csharp-main` + `hello-csharp-slave`, 2 Services. Shared service-level fields (`repo`, `owner`) inherited from `service.yaml`.

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
