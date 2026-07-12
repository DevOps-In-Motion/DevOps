vagrant up

# Destroy the VMs
vagrant destroy -f


vagrant ssh controlplane
vagrant ssh worker1
vagrant ssh worker2

# switch to the nginx-deployer context
kubectl config use-context nginx-deployer-context