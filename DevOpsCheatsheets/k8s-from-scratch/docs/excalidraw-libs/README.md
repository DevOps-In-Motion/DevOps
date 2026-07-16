# Excalidraw libraries (workspace)

[`kubernetes-icons.excalidrawlib`](kubernetes-icons.excalidrawlib) — official K8s object icons
(ns, pod, deploy, svc, ing, secret, user, group, role, …) from
[excalidraw-libraries / boemska-nik](https://github.com/excalidraw/excalidraw-libraries).

**In Cursor / VS Code:** workspace setting
`excalidraw.workspaceLibraryPath` points here so Library panel loads these icons.

**On excalidraw.com:** Library → **⋯** → **Open** → select this `.excalidrawlib` file
(or Browse libraries → Kubernetes icons).

Slides that use this library:

- `../architecture.excalidraw` — Azure-style platform / traffic / AuthZ (external LB → cluster → dashed namespaces → App)
- `../networking.excalidraw` — assignment Pod ↔ Pod view (3 nodes, Calico on `eth1`)
