# Vagrantfile
Vagrant.configure("2") do |config|
  config.vm.box = "bento/ubuntu-24.04"  # or a 26.04 box once available

  # Fix DNS: force IPv4 public resolvers so hostname lookups (apt, k8s repos) work reliably
  config.vm.provision "shell", inline: <<-SHELL
    mkdir -p /etc/systemd/resolved.conf.d
    cat <<EOF > /etc/systemd/resolved.conf.d/dns.conf
[Resolve]
DNS=1.1.1.1 8.8.8.8
DNSSEC=yes
EOF
    systemctl restart systemd-resolved
  SHELL

  config.vm.define "controlplane" do |node|
    node.vm.network "private_network", ip: "192.168.56.101"
  end

  config.vm.define "worker1" do |node|
    node.vm.network "private_network", ip: "192.168.56.102"
  end

  config.vm.define "worker2" do |node|
    node.vm.network "private_network", ip: "192.168.56.103"
  end
end