# Ansible example 


This is an AI gen example. 1 control plane node and 8 worker nodes. 

**Configuration**

-  allowing for pods to only be scheduled if they have a certain label.
-  resource requirements
-  and secrets injected for ssh connection


## Key Features:

**1. Pod Scheduling with Labels:**
- Worker nodes are labeled (e.g., `tier=frontend`, `tier=backend`)
- Nodes have taints applied (`restricted=true:NoSchedule`)
- Pods must have tolerations and node selectors to be scheduled
- Example deployment shows how to target specific labeled nodes

**2. Resource Requirements:**
- `LimitRange` configured for default resource requests/limits per container
- `ResourceQuota` set at namespace level to manage total cluster resources
- Min/max/default CPU and memory specifications included
- Example deployment demonstrates proper resource specification

**3. SSH Secrets Injection:**
- SSH credentials stored as Kubernetes secrets
- Secrets mounted as volumes in pods
- Environment variables populated from secret keys
- Example shows SSH key mounted at `/etc/ssh-keys/id_rsa` with proper permissions

## Usage:

```bash
# Run the full playbook
ansible-playbook -i inventory.ini playbook.yml

# Or run specific parts
ansible-playbook -i inventory.ini playbook.yml --tags "control_plane"
```

## Important Notes:

- Update IP addresses in `inventory.ini` to match your infrastructure
- Ensure SSH keys exist at `/root/.ssh/id_rsa` before running
- Modify the `node_label` values for different workload types
- Adjust resource limits based on your hardware specifications
- The example uses Kubernetes 1.28 and Calico CNI
