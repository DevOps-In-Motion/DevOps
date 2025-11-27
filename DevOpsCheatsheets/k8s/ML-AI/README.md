# Overview

The `ML-AI` folder contains Kubernetes manifests and supporting documentation for configuring, managing, and experimenting with GPU scheduling and partitioning strategies for machine learning and AI workloads. It demonstrates how to set up and use features such as NVIDIA GPU Operator, Multi-Instance GPU (MIG), time-slicing, node taints, resource quotas, and GPU-aware pod deployment. These resources help enable multiple containers or users to efficiently share GPU resources within a Kubernetes cluster for both production and research use cases.


# MIG v. Time-Slicing

| | MIG | Time-Slicing |
|---|---|---|
| **Partition Type** | Physical | Logical |
| **Max Partitions** | 7 | Unlimited |
| **SM QoS** | Yes | No |
| **Memory QoS** | Yes | No |
| **Error Isolation** | Yes | No |
| **Reconfigure** | Requires Reboot | Dynamic |
| **GPU Support** | H100, A100, A30 | Most GPU |

## Use Cases 

Here are two use cases for each GPU partitioning approach:

## MIG (Multi-Instance GPU)

**Use Case 1: Multi-Tenant Cloud Environments**
Ideal for cloud service providers offering GPU resources to multiple customers. MIG provides strict hardware isolation with guaranteed QoS, ensuring one tenant's workload can't impact another's performance or access their memory. Perfect for SaaS platforms where different customers run AI inference workloads simultaneously.

**Use Case 2: Production ML Inference with SLA Requirements**
Best for organizations running multiple production inference services that need predictable, consistent performance with strict SLAs. The hardware isolation and memory/SM QoS ensure each service gets dedicated resources without interference, critical for applications like real-time fraud detection or medical imaging analysis where response time consistency matters.

## Time-Slicing

**Use Case 1: Development and Testing Environments**
Perfect for development teams where multiple data scientists need GPU access for experimentation, model training, and prototyping. The unlimited partitions and dynamic reconfiguration allow flexible resource sharing without reboots. Lower priority for isolation makes it cost-effective for non-production workloads.

**Use Case 2: Batch Processing and Research Workloads**
Ideal for academic institutions or research labs running various ML experiments and batch jobs that don't require guaranteed QoS. Multiple researchers can share GPU resources across different projects, with the scheduler managing access. The broad GPU compatibility means it works with existing hardware investments.