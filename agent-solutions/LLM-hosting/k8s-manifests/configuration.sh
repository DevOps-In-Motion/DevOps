kubectl create ns gpu-operator
# If your cluster uses Pod Security Admission (PSA) to restrict the behavior of pods, 
# label the namespace for the Operator to set the enforcement policy to privileged:
kubectl label --overwrite ns gpu-operator pod-security.kubernetes.io/enforce=privileged


helm repo add nvidia https://helm.ngc.nvidia.com/nvidia \
    && helm repo update

helm install --wait --generate-name \
    -n gpu-operator --create-namespace \
    nvidia/gpu-operator \
    --version=v25.10.0

helm install --wait --generate-name \
    -n gpu-operator --create-namespace \
    nvidia/gpu-operator \
    --version=v25.10.0 \
    --set <option-name>=<option-value>



### Taints for Nodes ###
# Dedicated nodes for GPU workloads
# Pods not requesting GPU resources should not be scheduled on GPU nodes

kubectl taint nodes node1 nvidia.com/gpu:NoSchedule


### Muti-Instance-GPU ###
# https://github.com/nvidia/mig-parted
# This will take 1 GPU and expose x amount of resources for integer based resources
# allows one to partition a GPU into a set of "MIG Devices"
# NOTE: The Nvidia operator uses the mig-parted plugin already. No need to install.
# Just create the config map, restart your manager, and go!
kubectl label node $NODE nvidia.com/mig.config=all-1g.5gb