sudo systemctl enable kubelet
sudo kubeadm token create --print-join-command 
sudo systemctl status kubelet
sudo systemctl is-active crio
sudo crictl ps -a

sudo ss -tlnp | grep 6443

sudo journalctl -u kubelet -n 50 --no-pager

# full reset of the cluster
sudo kubeadm reset -f
sudo rm -rf /etc/cni/net.d
sudo rm -rf /var/lib/kubelet/*
sudo systemctl stop kubelet

sudo kubeadm init --config ~/kubeadm.config

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

kubectl get nodes