kubectl taint nodes worker1 workload=nginx:NoSchedule --overwrite
kubectl taint nodes worker2 workload=nginx:NoSchedule --overwrite
