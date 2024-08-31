#!/bin/bash

# Default settings to enable all components
ENABLE_ISTIO=true
ENABLE_METALLB=true
ENABLE_CALICO=true

# Function to display usage instructions
function show_usage() {
    echo "Usage: $0 [--no-istio] [--no-metallb] [--no-calico]"
    echo "Options:"
    echo "  --no-istio     Disable Istio installation"
    echo "  --no-metallb   Disable MetalLB installation"
    echo "  --no-calico    Disable Calico installation"
    exit 1
}

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --no-istio) ENABLE_ISTIO=false ;;
        --no-metallb) ENABLE_METALLB=false ;;
        --no-calico) ENABLE_CALICO=false ;;
        *) echo "Unknown parameter passed: $1"; show_usage ;;
    esac
    shift
done

# Function to setup containerd and Kubernetes essentials
function setup_containerd_k8s() {
    cat <<EOF > /tmp/setup_containerd.sh
#!/bin/bash
set -e

# Install prerequisites and configure containerd
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo chmod 644 /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update

# Configure sysctl parameters for Kubernetes networking
cat <<SYSCTL | sudo tee /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
SYSCTL

modprobe br_netfilter
sudo sysctl --system

# Stop and disable apparmor
sudo systemctl stop apparmor
sudo systemctl disable apparmor --now

# Install containerd
sudo apt-get install containerd -y
mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
sudo sed -i 's/pause:3.8/pause:3.9/g' /etc/containerd/config.toml
crictl config --set runtime-endpoint=unix:///run/containerd/containerd.sock --set image-endpoint=unix:///run/containerd/containerd.sock
sudo systemctl daemon-reload
sudo systemctl restart containerd.service

# Install Kubernetes components
sudo apt-get install kubeadm kubelet kubernetes-cni -y

# Setup CSI LVM
sudo truncate -s 1024G /tmp/disk.img
sudo losetup -f /tmp/disk.img --show
sudo pvcreate /dev/loop0
sudo vgcreate lvmvg /dev/loop0
EOF

    # Distribute and execute the setup script on all nodes
    for node in worker01 worker02 worker03; do
        scp /tmp/setup_containerd.sh $node:/tmp/setup_containerd.sh
        ssh $node "bash /tmp/setup_containerd.sh"
    done
    ssh master01 "bash /tmp/setup_containerd.sh"
}

# Function to initialize Kubernetes master node
function setup_master() {
    cat <<EOF > /tmp/setup_k8s.sh
#!/bin/bash
set -e

IP=\$(ip a show ens33 | grep "192.168" | cut -d " " -f6 | cut -d"/" -f1)
HOST=\$(hostname)

# Pull necessary images and initialize Kubernetes
kubeadm config images pull
sudo apt-get install kubectl -y

kubeadm init --cri-socket /run/containerd/containerd.sock --apiserver-advertise-address \$IP --control-plane-endpoint \$IP --pod-network-cidr 192.168.0.0/16 --node-name \$HOST --v=7

# Setup kubeconfig for kubectl access
export KUBECONFIG=/etc/kubernetes/admin.conf
mkdir -p /root/.kube
sudo cp -i /etc/kubernetes/admin.conf /root/.kube/config
echo 'source <(kubectl completion bash)' >> /root/.bashrc

# Wait for the master node to be ready
while [ \$(kubectl get nodes --no-headers | grep -c master01) -ne 1 ]; do sleep 10; done

# Apply Calico if enabled
if [ "$ENABLE_CALICO" = true ]; then
    wget https://raw.githubusercontent.com/projectcalico/calico/v3.27.3/manifests/calico.yaml -O /tmp/calico.yaml
    kubectl apply -f /tmp/calico.yaml
fi

# Generate node join command
kubeadm token create --print-join-command --ttl 0 2>/dev/null | tee /tmp/node-join.sh
EOF

    bash /tmp/setup_k8s.sh
}

# Function to join worker nodes to the cluster
function join_workers() {
    for node in worker01 worker02 worker03; do
        scp /tmp/node-join.sh $node:/tmp/node-join.sh
        ssh $node "bash /tmp/node-join.sh"
        ssh $node "rm -f /tmp/setup_containerd.sh /tmp/node-join.sh"
    done
}

# Function to setup MetalLB
function setup_metallb() {
    if [ "$ENABLE_METALLB" = true ]; then
        wget https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml -O /tmp/metallb-native.yaml

        # Enable strict ARP mode in kube-proxy
        kubectl get configmap kube-proxy -n kube-system -o yaml | sed -e "s/strictARP: false/strictARP: true/" | kubectl apply -f - -n kube-system

        # Apply MetalLB configuration
        kubectl apply -f /tmp/metallb-native.yaml

        cat <<EOF > /tmp/metallb-address-pool.yaml
---
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: first-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.90.240-192.168.90.245

---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: myl2adv
  namespace: metallb-system
EOF
        kubectl apply -f /tmp/metallb-address-pool.yaml
    fi
}

# Function to setup Helm and OpenEBS for persistent storage
function setup_helm_openebs() {
    # Install Helm
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh

    # Install OpenEBS via Helm
    helm repo add openebs https://openebs.github.io/openebs
    helm repo update
    helm install openebs --namespace openebs openebs/openebs --set engines.replicated.mayastor.enabled=false --set engines.local.zfs.enabled=false --create-namespace

    # Apply LVM Storage Class configuration
    cat <<EOF > /tmp/lvm-storage-class.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: openebs-lvmpv
parameters:
  storage: "lvm"
  volgroup: "lvmvg"
provisioner: local.csi.openebs.io
EOF
    kubectl apply -f /tmp/lvm-storage-class.yaml
}

# Function to setup Istio
function setup_istio() {
    if [ "$ENABLE_ISTIO" = true ]; then
        curl -L https://istio.io/downloadIstio | sh -
        cp istio-1.*/bin/istioctl /usr/local/bin/
        istioctl install --set profile=demo -y

        # Create a test namespace with Istio sidecar injection enabled
        kubectl create ns test-ns
        kubectl label namespace test-ns istio-injection=enabled
    fi
}

# Main script execution
setup_containerd_k8s
setup_master
join_workers
setup_metallb
setup_helm_openebs
setup_istio

# Cleanup temporary files
rm -f /tmp/setup_containerd.sh /tmp/setup_k8s.sh /tmp/node-join.sh /tmp/metallb-address-pool.yaml /tmp/lvm-storage-class.yaml ./get_helm.sh

echo "Kubernetes cluster setup is complete. Lab is ready to test."
