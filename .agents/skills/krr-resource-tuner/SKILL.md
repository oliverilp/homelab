---
name: krr-resource-tuner
description: Use when the user provides Robusta KRR output and wants this homelab repo's Kubernetes manifests or Helm values updated with rounded CPU and memory resource requests/limits.
---

# Homelab KRR Resource Tuner

Use this skill when the user pastes `krr simple` output and asks Codex to decide final Kubernetes resource values, then update this homelab repository.

The source of truth is the pasted KRR recommendation. KRR simple already uses CPU percentile and memory max plus buffer, so do not add another percentage buffer. Your job is to make values operationally nice: always round up, keep small workloads precise enough, and make larger workloads use cleaner numbers.

## Workflow

1. Parse the pasted KRR output into rows with:
   - namespace
   - workload kind
   - workload name
   - container name
   - recommended CPU request
   - recommended CPU limit
   - recommended memory request
   - recommended memory limit
2. Use target values after `->`; ignore diff values like `+10m`, `-72Mi`, and aggregate markers like `(2 pods)`.
3. Carry namespace, workload name, kind, and pod counts from previous table rows when KRR omits them for additional containers in the same workload.
4. If the table is wrapped or truncated, recover exact workload/container names from preceding log lines such as `Calculated recommendations for Deployment namespace/name/container`.
5. If a row has `?`, `No data`, or `Not enough data`, skip it and leave that container unchanged.
6. Search `k8s/` for the source configuration that owns the workload. Edit only source manifests or Helm values committed in this repo.
7. Update container resources. Do not touch PVC `resources.requests.storage`.
8. Validate changed YAML and summarize every changed workload/container.

If pasted table output is too truncated to safely map a row to one exact source object, stop and ask the user for either wider table output or structured KRR output, preferably:

```bash
krr simple -p http://127.0.0.1:9090 --history_duration 504 -f yaml
```

## Rounding Algorithm

Always round up. Never round to nearest. Never round down.

Do not apply a multiplier like 1.5. The KRR memory recommendation already includes peak memory plus its configured buffer.

### CPU Requests

Normalize CPU to millicores before rounding. Examples: `1` is `1000m`, `0.5` is `500m`.

Use this function:

```text
cpu_m = max(krr_cpu_m, 10)

if cpu_m <= 250:       step = 10
elif cpu_m <= 1000:    step = 25
elif cpu_m <= 2000:    step = 50
else:                  step = 100

final_cpu_request = ceil(cpu_m / step) * step
```

Write CPU requests as millicores, for example `10m`, `110m`, `500m`, `1500m`.

Examples:

- `10m` -> `10m`
- `42m` -> `50m`
- `109m` -> `110m`
- `490m` -> `500m`
- `1473m` -> `1500m`

### CPU Limits

KRR simple normally recommends CPU limit `unset`. When KRR says CPU limit `unset`, remove `limits.cpu` from the manifest or values file.

Do not invent CPU limits unless the pasted KRR output explicitly recommends one or the user explicitly asks for CPU limits.

### Memory Requests And Limits

Normalize memory to Mi before rounding. Examples: `1Gi` is `1024Mi`, `2Gi` is `2048Mi`.

Use this function for both memory request and memory limit:

```text
mem_mi = max(krr_memory_mi, 100)

if mem_mi <= 256:       step = 10
elif mem_mi <= 1024:    step = 50
elif mem_mi <= 4096:    step = 100
elif mem_mi <= 8192:    step = 250
else:                   step = 500

final_memory = ceil(mem_mi / step) * step
```

Write memory as:

- `Mi` for non-exact Gi values, for example `140Mi`, `550Mi`, `1500Mi`, `4500Mi`.
- `Gi` only for clean whole Gi values, for example `1Gi`, `2Gi`, `4Gi`.

Examples:

- `20Mi` -> `100Mi`
- `100Mi` -> `100Mi`
- `134Mi` -> `140Mi`
- `293Mi` -> `300Mi`
- `764Mi` -> `800Mi`
- `1051Mi` -> `1100Mi`
- `1407Mi` -> `1500Mi`
- `4415Mi` -> `4500Mi`

## Homelab Policy

- Availability is more important than tiny absolute savings, but avoid large arbitrary buffers.
- Memory floor is `100Mi` for both request and limit, including idle Go/Rust services that KRR reports below that.
- CPU request floor is `10m`.
- Memory request and memory limit should normally be the same rounded value because KRR simple recommends both from the same peak-plus-buffer calculation.
- CPU limits should normally be unset.
- Keep existing workload-specific intent only when a manifest comment or user instruction clearly justifies it; otherwise use the rounded KRR target.
- Jellyfin exception: for namespace `jellyfin`, workload `jellyfin`, container `jellyfin`, use at least `2Gi` memory request and `2Gi` memory limit, even if KRR recommends around `1400Mi`. If KRR recommends less than `2Gi`, use `2Gi`, not the current larger value merely because it already exists. If KRR recommends more than `2Gi`, round up using the normal memory tiers.
- Do not create new special cases unless the user states one or the existing manifest clearly documents one.

## Editing Source Files

Prefer exact source files in this repo:

- Plain Kubernetes manifests: update the container under `.spec.template.spec.containers`.
- CronJobs: update the container under `.spec.jobTemplate.spec.template.spec.containers`.
- Dragonfly resources: update the CR `spec.resources` for the Dragonfly container when KRR reports a Dragonfly StatefulSet container.
- Helm-managed apps: update the committed values file that ArgoCD uses, such as `k8s/argocd/argocd-values.yaml`, `k8s/monitoring/prometheus-stack-values.yaml`, or `k8s/<app>/*-values.yaml`.

Use `rg` to map rows to files. Useful searches:

```bash
rg -n "name: <workload>|namespace: <namespace>|name: <container>|resources:" k8s
rg -n "<workload>|<container>|resources:" k8s/<app>
```

Be careful with Helm values because the key names may differ from Kubernetes workload names. Inspect the local values file and ArgoCD Application source before editing. If the chart values file does not already expose resource settings for the target component, do not guess a new chart-specific path unless the chart's local values pattern makes it obvious.

Preserve local style where reasonable:

- Keep comments.
- Keep existing key order when possible: `resources`, `requests`, then `limits`.
- Remove empty `limits` maps after deleting `limits.cpu` only if no memory limit remains.
- Do not rewrite unrelated YAML.

## Validation

After edits:

1. Run `git diff --check`.
2. For changed plain manifest directories, run:

```bash
kubectl apply --dry-run=client --validate=false -f k8s/<app-or-dir>
```

3. For changed Helm values, run a local YAML parse or a chart render if the chart is available locally. If rendering requires network or cluster access, say that validation was limited.
4. Review the diff manually and ensure no PVC storage request was changed by mistake.

## Final Response

Report:

- which KRR history/output was used if visible
- each changed namespace/workload/container
- final CPU request, CPU limit state, memory request, and memory limit
- changed file paths
- validation commands run

Mention skipped rows and why, especially `No data`, `Not enough data`, or ambiguous truncated table rows.
