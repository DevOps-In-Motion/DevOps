# k8s-from-scratch

Local Kubernetes lab on **Vagrant + VirtualBox**: one control plane and two workers, plus an HA nginx app with RBAC, Ingress, and cert-manager TLS.

## Host requirements

| Requirement | Minimum | Recommended |
| --- | --- | --- |
| **CPU** | 6 cores (vCPUs for guests) | **8+ cores** |
| **RAM** | 10 GB free for VMs | **16 GB** system RAM |
| **Disk** | 30 GB free | **40+ GB** free |
| **OS** | macOS, Linux, or Windows with VT-x/AMD-V | — |

### Guest VM sizing (recommended)

The active `Vagrantfile` does not pin provider resources; size each VM as follows (or set `vb.cpus` / `vb.memory` in the VirtualBox provider block):

| VM | vCPUs | RAM | Role |
| --- | ---: | ---: | --- |
| `controlplane` | 2 | **4096 MB** | API server, etcd, controllers, scheduler |
| `worker1` | 2 | **2048 MB** | Workloads (nginx replica + system pods) |
| `worker2` | 2 | **2048 MB** | Workloads (nginx replica + system pods) |
| **Total** | **6** | **~8 GB** | — |

kubeadm needs at least 2 CPU on the control plane; 4 GB RAM is safer once Calico, Ingress, and cert-manager are running.

## Software versions

Tested on this project’s host:

| Tool | Version (tested) | Notes |
| --- | --- | --- |
| **Vagrant** | **2.4.9** | Use **2.4.x** or newer |
| **VirtualBox** | **7.2.8** | Use **7.0+** (7.2.x preferred) |
| **Box** | `bento/ubuntu-24.04` | Ubuntu 24.04 guest |
| **Kubernetes** | **v1.36** | Installed via kubeadm |
| **CRI-O** | **v1.36** | Container runtime |
| **CNI** | Calico (Tigera operator) | Pod networking |
| **Helm** | 3.x | Used for cert-manager |
| **cert-manager** | **v1.17.2** | Helm chart from Jetstack |

Also useful on the host: `kubectl`, `helm`, and (optional) the [Excalidraw](https://excalidraw.com) app/extension to open the architecture diagram.

## Cluster topology

| Node | Host-only IP | Notes |
| --- | --- | --- |
| `controlplane` | `192.168.56.101` | API at `https://192.168.56.101:6443` |
| `worker1` | `192.168.56.102` | Tainted `workload=nginx:NoSchedule` for the app |
| `worker2` | (add `192.168.56.103` if desired) | Same nginx taint; HA replica |

Workers run **2 nginx replicas** in namespace `nginx-app` with pod anti-affinity (one pod per node). RBAC binds user `nginx-deployer` to `nginx-deployer-role`. TLS for `nginx.local` is issued by cert-manager into Secret `nginx-tls` and attached to the Ingress.

## Quick start

```bash
make up          # boot VMs (controlplane + workers)
make all         # context → CNI → labels → metrics → RBAC → cert-manager → taints → nginx → TLS
make status      # nodes / nginx / cert-manager
# optional: make user   # nginx-deployer client cert + context
```

Or step through with `make help`.

Architecture diagram: [`docs/architecture.excalidraw`](docs/architecture.excalidraw) (open in [excalidraw.com](https://excalidraw.com) or the VS Code / Cursor Excalidraw extension).
