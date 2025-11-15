### Network ns
# add network namespace
ip netns add <name>
# 
ip link 
#
ip addr
# allows you to run the ip link command inside the network namespace
ip netns exec <name> ip link # aka $ ip -n <name> link
# link network namespaces
ip link set <name> netns <name>  
# create a virtual switch - linux bridge - interface that operates like a switch
ip link add <name> type bridge
# set up
ip link set dev <name> up


### ----- Kubernetes Network admin for on prem ----- ###

### copy stdin to file and stdout
sudo tee /etc/sysctl.d/k8s.conf <<EOF
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
EOF

sudo modprobe br_netfilter



