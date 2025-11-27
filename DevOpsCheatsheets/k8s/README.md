# Kubernetes Templates & Cheatsheets

This folder contains a curated collection of useful Kubernetes manifests, templates, and configuration notes. It is meant as a quick reference and toolkit for deploying, managing, and experimenting with clusters—especially focused on GPU workloads, multi-tenancy, advanced scheduling, and general best practices.

## Folder Structure & Contents

- **ML-AI**:  
  Manifests and configs for advanced GPU scheduling, partitioning (NVIDIA MIG, time-slicing), and quota enforcement.  
  Includes:
  - Example pod specs requesting GPUs
  - Node configs for MIG and time-sliced resources
  - ConfigMaps for MIG partition schemes
  - ResourceQuota templates to limit GPU, CPU, memory, and storage use in namespaces

- **configuration.sh**:  
  Shell script with the key commands and Helm instructions to set up GPU operator, label/taint nodes, and enable advanced GPU sharing features.

- **General Structure**:
  - All files are provided as copy-paste ready YAML or shell scripts.
  - Useful for testing different configurations or as a starting-point for production clusters.
  - Some manifests are tailored for NVIDIA A100, H100, or other modern GPUs.

## What You’ll Find Here

- **Pod & Deployment Cheatsheets**  
  Common patterns for creating pods or deployments requesting GPU or CPU resources, with best-practice labels and requests/limits.
- **Node & MIG Configurations**  
  Examples showing how to expose and configure different GPU partitioning strategies, with nodeSelector and taints.
- **Resource Management**  
  Ways to use ResourceQuota and LimitRange to restrict and control resource usage per namespace—ideal for shared clusters.
- **Time-Slicing and Multi-Instance Examples**  
  Configs to enable multiple users or jobs to safely and efficiently share expensive GPU resources.
- **Quick Scripts**  
  Helper shell scripts for installing/patching GPU operators, tainting/labeling nodes, or applying new configmaps.
- **Comments and Links**  
  Most files include inline comments and reference links for further reading or to original sources.

## Best Practices Reminder

- Always adapt resource values (CPU, memory, GPU) to match your hardware and workload needs.
- Review and test in a sandbox before rolling these settings into production clusters.
- Follow security best practices: limit privileges, and use namespace isolation for multi-tenancy.

***

If you have suggestions, or new templates to add to this cheatsheet folder, open a PR or drop an issue!

