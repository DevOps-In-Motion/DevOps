# K3D: Run wiki stack in a local cluster

**Intended run:** Use the DinD image with **`--privileged`** and **no Docker socket** (no `-v /var/run/docker.sock`). Socket mount is only a fallback if DinD fails.

## Does the entrypoint work?

**Yes.** The script is correct and should work for a **first run** on a machine with Docker and no existing cluster named `wiki`.

### What the script does (and why it works)

| Step | What it does | Why it works |
|------|----------------|---------------|
| **1** | Creates k3d cluster `wiki` with **8080→80**, **8443→443**; **Traefik is kept** (K3s default) | No nginx install; works in DinD without socket. |
| **2** | `helm dependency update` in wiki-chart | Pulls postgresql and kube-prometheus-stack per `Chart.yaml`. |
| **3** | `helm upgrade --install wiki` with `k3d/values.yaml` | Ingress uses **Traefik** (className: traefik); postgres, prometheus stack, Grafana. |
| **4** | Done | API and Grafana on port 8080. |

So:

- **API:** `http://localhost:8080/users`, `http://localhost:8080/posts` — Traefik (K3s default) routes to the wiki backend.
- **Grafana:** `http://localhost:8080/grafana` — same port, path `/grafana`, backend `wiki-grafana:80`.
- **Database:** Wiki app gets `DATABASE_URL` from the chart-built secret; host is `wiki-postgresql` (Bitnami subchart service).

Values in `k3d/values.yaml`: `ingress.className: traefik`, `postgresql.enabled` + `auth`, `prometheusStack.enabled`, `prometheus-stack.enabled`.

### When it can fail

1. **Cluster already exists**  
   Second run without deleting: `k3d cluster create wiki` fails (cluster name in use).  
   **Fix:** Delete first: `k3d cluster delete wiki`, then run again.

2. **Docker socket**  
   With **socket** mount, k3d runs on the host. **Without socket** (DinD), use the DinD image and Traefik (default); no nginx install.

3. **Image pull / network**  
   If `public.ecr.aws/i3h9f2j0/demos/wiki-backend:latest` or Helm repos are unreachable, install will fail.  
   **Fix:** Ensure network access and image availability (or override `image.repository` / `image.tag` in values).

4. **No space left on device (DinD)**  
   The inner Docker needs several GB for k3d-tools and k3s images. If the container runs out of disk, pulls fail.  
   **Fix:** Free host disk; run `docker system prune -af` and remove old containers/images; or use the socket-based run so k3d uses the host’s Docker and disk.

5. **Grafana**  
   Login is always **admin / admin** (set in `k3d/values.yaml` via `prometheus-stack.grafana.adminPassword`).

### Quick run: privileged DinD (no Docker socket) — recommended

Run with **`--privileged`**. **Do not** mount the host Docker socket.

**Requirements:**

- **Linux host** is most reliable (DinD on Docker Desktop for Mac often hits cgroup/VM limits and hangs).
- **Do not set a memory limit** on the container (or give it **≥ 6GB**). The inner Docker + k3d cluster need headroom.
- **At least ~5GB free disk** for the DinD container (k3d/k3s images). A full run (DinD + wiki-data volume) typically uses **~10–12GB** in Docker volumes and images. To reclaim after stopping the container: `docker volume prune -f` (and `docker system prune -af` if needed). If you see `no space left on device`, free space and prune; or use the 5GB cap script or the socket fallback below.
- Use the **exact** run below (`--privileged`, `--cgroupns=host`, **no** `-v docker.sock`).

From repo root:

```bash
# Build the DinD image (k3d, helm, kubectl; inner dockerd uses vfs; no socket)
docker build -f Dockerfile.dind -t wiki-k3d-dind .

# Run: privileged, no socket. Add -v wiki-data:/data to persist Postgres across container restarts.
docker run --rm -it --privileged --cgroupns=host -p 8080:8080 -p 8443:8443 -v wiki-data:/data wiki-k3d-dind
```

Or use the helper script: `./testing/test-k3d.sh` (builds then runs with privileged, no socket, and `wiki-data:/data` for persistence).

**Data persistence (Option 1):** With `-v wiki-data:/data`, Postgres data is stored on the host volume `wiki-data`. If you stop the container and start a new one (same volume), the new cluster will use the same data after Helm install runs again.

**Capping DinD disk to 5GB (Linux only):** Docker has no per-container disk limit. To cap the inner Docker (and thus k3d images/containers) at 5GB, use a 5GB filesystem mounted at `/var/lib/docker`:

```bash
# From repo root (Linux). Creates a 5GB image, mounts it, runs DinD with that as inner Docker data.
chmod +x ./k3d/run-dind-5g.sh
./k3d/run-dind-5g.sh
```

The script creates `k3d/dind-5g-data/dind-5g.img` (5GB), mounts it at `k3d/dind-5g-data/mount`, and runs the container with `-v .../mount:/var/lib/docker`. Optional: `DIND_5G_DIR=/path DIND_5G_SIZE_MB=5120 ./k3d/run-dind-5g.sh`. On **Mac/Windows** there is no built-in per-container cap; limit overall Docker disk in Docker Desktop → Settings → Resources → Disk image size.

Then open: **http://localhost:8080/users**, **http://localhost:8080/posts**, **http://localhost:8080/grafana** (admin / admin).

### Fallback: host Docker socket

If DinD fails (cgroups, hang, etc.), use the socket-based image instead (uses host Docker):

```bash
docker build -t wiki-k3d .
docker run --rm -it -v /var/run/docker.sock:/var/run/docker.sock wiki-k3d
```

Then open: **http://localhost:8080/users**, **http://localhost:8080/posts**, **http://localhost:8080/grafana** (admin / admin).

**On a Linux host**, if you still see cgroup errors, try adding a cgroup mount:

```bash
docker run --rm -it --privileged --cgroupns=host \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  -p 8080:8080 -p 8443:8443 wiki-k3d-dind
```

**If it hangs** (no new output for 5+ min):  
- **DinD**: Often due to limited Docker memory/CPU or the inner K3s node not starting. Give Docker at least **4GB RAM**.  
- **Stuck at “Waiting for API server”**: The K3s server node may have failed to start; try again or use the socket-based run.  
- **Stuck at step 5**: Helm is waiting for all pods (Postgres, Prometheus, Grafana, wiki) to be Ready; you’ll now see “... still installing (N min)” every minute. If it still doesn’t finish within ~10 min, switch to the socket-based run (below).

**If you see cgroup errors** (e.g. `failed to write subtree controllers` / `no such file or directory` on `cgroup.subtree_control`): DinD often fails on Docker Desktop for Mac or hosts with cgroups v2. Use the **socket-based run** instead (same result, uses host Docker):  
`docker build -t wiki-k3d . && docker run --rm -it -v /var/run/docker.sock:/var/run/docker.sock wiki-k3d`

To tear down (socket run: on host; DinD run: not applicable—cluster is gone when the container exits).
