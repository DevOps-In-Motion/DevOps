# change the editor to nano for k edit
export KUBE_EDITOR='nano'

alias k=kubectl

###  ----- Scaling ----- ###
kubectl autoscale deployment <deplyment> --cpu=50% --min=1 --max=10


### ----- Deployments ----- ###

# Check if deployment is running
kubectl get deployment -n logging-ns

# Check pod status
kubectl get pods -n logging-ns

# Get detailed information
kubectl describe deployment logging-deployment -n logging-ns

# Get the pod name first
kubectl get pods -n logging-ns

# Check logs from the app-container
kubectl logs <pod-name> -n logging-ns -c app-container

# Or follow logs in real-time
kubectl logs <pod-name> -n logging-ns -c app-container -f


### ----- Services ----- ###

# Create a service messaging-service to expose the messaging application within the cluster on port 6379.
kubectl expose pod messaging --name=messaging-service --port=6379
# Expose service for deployment for app, svc type nodeport, at container ports
kubectl expose deployment hr-web-app --type=NodePort --name=hr-web-app-service --port=6379 --target-port=30082
service/hr-web-app-service exposed

# use curl to test services
curl -s http://kodekloud-ingress.app/ # endpoint

### ----- service accounts - sa ----- ###
k create serviceaccount 

# Create a new ClusterRole named deployment-clusterrole, which only allows to create the following resource types:
# Deployment
# Stateful Set
# DaemonSet
kubectl create clusterrole deployment-clusterrole --verb=create --resource=Deployment,StatefulSet,DaemonSet
kubectl create sa cicd-token --namespace <ns>
kubectl create clusterrolebinding <deploy-b> --clusterrole=deployment-clusterrole --serviceaccount=<ns>:<service-account-name>


# Set the node named ek8s-node-0 as unavailable and reschedule all the pods running on it.



### ----- Updating ----- ###

# deployment rolling update
kubectl set image deployments/nginx-deploy nginx=nginx:1.17.0



### ----- System Admin ----- ###
# 
# create a new user



### ----- Certs ----- #####

# Create the CertificateSigningRequest
# encode csr
# First you should find and cat the CSR
cat /root/CKA/john.csr | base64 | tr -d "\n" # or $(cat /root/CKA/john.csr | base64 -w 0)

cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: john-developer
spec:
  request: $(cat /root/CKA/john.csr | base64 -w 0)
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400
  usages:
  - client auth
EOF

# Approve the CSR
kubectl certificate approve john-developer

# Verify it's approved
kubectl get csr john-developer

# Get the signed certificate
kubectl get csr john-developer -o jsonpath='{.status.certificate}' | base64 -d > /root/CKA/john.crt

# Set the credentials for john
kubectl config set-credentials john --client-key=/root/CKA/john.key --client-certificate=/root/CKA/john.crt --embed-certs=true

# Create a context for john
kubectl config set-context john-context --cluster=kubernetes --user=john

# Optional: Test by switching context
kubectl config use-context john-context

# Switch back to admin context
kubectl config use-context kubernetes-admin@kubernetes


### ------ Taints ----- ###

kubectl taint nodes node01 key1=value1:NoSchedule
kubectl taint nodes node01 spray=mortein:NoSchedule


### ------ Networking ----- ###

## example
# You are an administrator preparing your environment to deploy a 
# Kubernetes cluster using kubeadm. Adjust the following 
# network parameters on the system to the following values, 
# and make sure your changes persist reboots:

# net.ipv4.ip_forward = 1
# net.bridge.bridge-nf-call-iptables = 1




# check DNS
kubectl logs --namespace=kube-system -l k8s-app=kube-dns

### DNS testing
# Create a busybox pod for DNS lookup of the service
kubectl run test-nslookup --image=busybox:1.28 \
  --rm -it \
  --restart=Never -- nslookup nginx-resolver-service > /root/CKA/nginx.svc

# If the above command doesn't redirect properly, use this alternative:
kubectl run test-nslookup --image=busybox:1.28 --rm -it --restart=Never -- nslookup nginx-resolver-service

# Get the IP of the nginx-resolver pod and replace the dots(.) with hyphon(-) which will be used below.
kubectl get pod nginx-resolver -o wide
kubectl run test-nslookup --image=busybox:1.28 --rm -it --restart=Never -- nslookup <P-O-D-I-P.default.pod> > /root/CKA/nginx.pod

# Get the pod IP
export POD_IP=$(kubectl get pod nginx-resolver -o jsonpath='{.status.podIP}')

# Convert IP to DNS format (replace dots with dashes)
export POD_IP_DASHED=$(echo $POD_IP | tr '.' '-')

# Get namespace (usually 'default')
NAMESPACE=$(kubectl get pod nginx-resolver -o jsonpath='{.metadata.namespace}')

# Perform DNS lookup for pod
kubectl run test-nslookup --image=busybox:1.28 \
  --rm --restart=Never -- nslookup pod.pod.cluster.local > /root/CKA/nginx.pod


kubectl run test-nslookup --image=busybox:1.28 \
  --rm -it --restart=Never -- nslookup mysql

# from the HR pod do a nslookup for the mysql service and save that to a file.
kubectl exec hr -- nslookup mysql.payroll > /root/CKA/nslookup.out

# Get the DNS service IP
kubectl get svc -n kube-system

# Look for kube-dns or coredns service: describe to figrue out the DNS provider
kubectl describe svc kube-dns -n kube-system

# Get just the cluster IP
kubectl get svc kube-dns -n kube-system -o jsonpath='{.spec.clusterIP}'

# check the CIDR range before installing a CNI
kubectl get node controlplane -o jsonpath='{.spec.podCIDR}' > /root/pod-cidr.txt



### ----- Static Pods ----- ###
ssh root@node01
# search for static pod path on host
# Check the kubelet config for static pod path
cat /var/lib/kubelet/config.yaml | grep staticPodPath

# Create the manifest file
cat > /etc/kubernetes/manifests/nginx-critical.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: nginx-critical
  namespace: default
spec:
  containers:
  - name: nginx
    image: nginx
    ports:
    - containerPort: 80
  restartPolicy: Always
EOF


### ----- Helm ----- ###
# find the helm deployments with the image called webapp-color
kubectl get deployments --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.spec.template.spec.containers[*].image}{"\n"}{end}' | grep "kodekloud/webapp-color:v1"



# switch context to node-name
kubectl config use-context <context-name>

# pods
kubectl run <pod> --image=nginx nginx
kubectl run custom-nginx --image=nginx --port=8080

kubectl run httpd --image=httpd:alpine --port=80 --expose
kubectl run redis --image=redis:alpine -l 'tier=db'

kubectl run --restart=Never --image=busybox static-busybox --dry-run=client -oyaml --command -- sleep 1000 > /etc/kubernetes/manifests/static-busybox.yamlkubectl create deployment --image=nginx nginx --replicas=4 --dry-run=client -o yaml > nginx-deployment.yaml 

# deploy

kubectl create deployment blue --image=nginx --replicas=3 --dry-run=client -o yaml > deploy.yaml 
kubectl create deployment webapp --image=kodekloud/webapp-color --replicas=3
kubectl create deployment redis-deploy --image=redis --replicas=2 -n dev-ns



# service
kubectl create service clusterip httpd --tcp=80:80
kubectl create service clusterip messaging-service --tcp=6379:6379 --dry-run=client -o yaml > messaging.yaml 
kubectl expose pod messaging --port=6379 --name messaging-service


### Taints / Tolerance

kubectl taint nodes <node-name> key=value:<taint-effect>



### Certificates
cat /etc/kubernetes/manifests/kube-apiserver.yaml
ls /etc/kubernetes/pki/
ls /etc/kubernetes/pki/etcd/
# What is the Common Name (CN) configured on the Kube-API Server certificate?
openssl x509 -in <file-path.crt> -text -noout
openssl x509 -in /etc/kubernetes/pki/apiserver.crt -text -noout
# What is the Common Name (CN) configured on the ETCD Server certificate?
openssl x509 -in /etc/kubernetes/pki/etcd/server.crt -text -noout

# What is the name of the CA who issued the Kube API Server Certificate?
kubectl describe certificatesigningrequests.certificates.k8s.io


# Kubectl suddenly stops responding to your commands. Check it out! 
# Someone recently modified the /etc/kubernetes/manifests/etcd.yaml file
docker ps -a | grep kube-apiserver

### Networking

echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
echo 'net.bridge.bridge-nf-call-iptables = 1' >> /etc/sysctl.conf
sysctl -p

sysctl net.ipv4.ip_forward
sysctl net.bridge.bridge-nf-call-iptables

# get ip address of controlplane
kubectl describe node controlplane
kubectl get nodes -o wide

# inspect the kubelet service and identify the container runtime endpoint
# What is the kubelet? The kubelet is a linux service that runs on the node.
ps -aux | grep -i kubelet | grep container-runtime-endpoint

# What is the path configured with all binaries of CNI supported plugins?
# ans: /opt/cni/bin

# What is the CNI plugin configured to be used on this kubernetes cluster?
ls /etc/cni/net.d/
# What binary exe file will be run by kubelet after a container and its ns are created?
cat /etc/cni/net.d/plugin.conflist

# see the interface that matches the ip of the thing
ip addr
# get more information about the interface
ip addr show <interface-name>

# what is the mac addr of node01
ssh node01
ip addr # get the mac addr

# We use containerd as our container runtime. What is the interface/bridge that is created by the runtime.
ip addr show type bridge

# If we tried to ping google from the node what route does it take? What is the default gateway?
ip route

# what port is scheduler listening on?
netstat -npl | grep -i scheduler

# check the port etcd is listening on
cat /etc/kubernetes/manifests/etcd.yaml


### ----- configmaps ---- ###
kubectl create cm trauerweide --from-literal tree=trauerweide
kubectl create configmap app-config -n cm-namespace \
  --from-literal=ENV=production \
  --from-literal=LOG_LEVEL=info

kubectl set env deployment/cm-webapp -n cm-namespace \
  --from=configmap/app-config



### ----- logs ----- ###
kubectl -n management logs deploy/collect-data -c container1 >> /root/logs.log
kubectl -n management logs deploy/collect-data -c container2 >> /root/logs.log
kubectl -n management logs --all-containers deploy/collect-data > /root/logs.log




##### ----- SRE K8S ------ #####

# check the api server
k -n kube-system get pod
# check the linux syslogs
journalctl | grep apiserver 
cat /var/log/syslog | grep apiserver # nothing specific
cat /var/log/pods/

# if pods aren't scaling check the kube manager-cluster
kubectl get pods -n kube-system



##### ----- Pods ----- #####
# distro-less pods aka only binary's in the pods
kubectl cp /local/path/to/file pod-name:/path/in/container
# this will get into the container
kubectl debug pod-name -it --image=busybox --target=container-name --share-processes
# one liner for to do something in the container: example kill the processq
kubectl debug pod-name -it --image=busybox --target=container-name --share-processes -- kill -USR1 1