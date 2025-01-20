#!/usr/bin/env bash

# Set Variables
WNODE=("worker01" "worker02" "worker03")
MNODE="master01"
K8S_VERSION="1.31" # Change this to your desired version (1.30, 1.31, 1.32)

# Utility Functions
show_progress() {
    local duration=$1
    local step=1
    for ((i = 0; i <= duration; i += step)); do
        printf "\r[%-50s] %d%%" "$(printf '#%.0s' $(seq 1 $((i * 50 / duration))))" "$((i * 100 / duration))"
        sleep $step
    done
    echo ""
}

log() {
    if [[ $VERBOSE -eq 1 ]]; then
        echo -e "[LOG] $@"
    fi
}

run_cmd() {
    if [[ $VERBOSE -eq 1 ]]; then
        eval "$@"
    else
        eval "$@" >/dev/null 2>&1
    fi
}

check_ssh_connection() {
    for node in "${WNODE[@]}" "$MNODE"; do
        log "Checking SSH connection for $node..."
        ssh "$node" "hostname" >/dev/null || {
            echo "Failed to connect to $node. Ensure SSH passwordless login is configured."
            exit 1
        }
    done
    echo "SSH connections are verified for all nodes."
}



setup_containerd() {
    local node=$1
    ssh "$node" "bash -s" <<EOF
#!/bin/bash
set -e

echo "net.ipv4.ip_forward = 1" | sudo tee /etc/sysctl.d/k8s.conf
echo "net.bridge.bridge-nf-call-iptables = 1" | sudo tee -a /etc/sysctl.d/k8s.conf
echo "net.bridge.bridge-nf-call-ip6tables = 1" | sudo tee -a /etc/sysctl.d/k8s.conf
sudo modprobe br_netfilter
sudo sysctl --system >/dev/null
sudo mkdir -p /etc/apt/keyrings
rm -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v$K8S_VERSION/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v$K8S_VERSION/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo DEBIAN_FRONTEND=noninteractive apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y containerd kubeadm kubelet kubectl >/dev/null
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
sudo sed -i -e 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
sudo sed -i 's|sandbox_image = "registry.k8s.io/pause:3.8"|sandbox_image = "registry.k8s.io/pause:3.10"|' /etc/containerd/config.toml
sudo systemctl daemon-reload
sudo systemctl restart containerd
EOF
    echo "Containerd and Kubernetes tools setup completed for $node."
}

setup_master_node() {
    log "Setting up the master node..."
    IP=$(hostname -I | awk '{print $1}')
    HOST=$(hostname)
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y kubectl
    sudo kubeadm config images pull
    sudo kubeadm init --cri-socket /run/containerd/containerd.sock --apiserver-advertise-address $IP --control-plane-endpoint $IP --node-name $HOST --v=5
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config
    echo 'source <(kubectl completion bash)' >>~/.bashrc
    kubeadm token create --print-join-command --ttl 0 > /tmp/node-join.sh
    log "Master node setup completed."
}

install_weave() {
    log "Installing Weave networking..."
    kubectl apply -f https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s.yaml
    show_progress 30
    kubectl wait -n kube-system --for=condition=Ready pod -l name=weave-net --timeout=600s
}

install_csi_longhorn() {
    log "Installing Longhorn CSI..."
    kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.7.2/deploy/longhorn.yaml
    show_progress 60
}

join_worker_nodes() {
    log "Joining worker nodes..."
    for node in "${WNODE[@]}"; do
        echo "Setting up worker node: $node..."
        scp "$MNODE:/tmp/node-join.sh" "$node:/tmp/node-join.sh"
        ssh "$node" "bash /tmp/node-join.sh"
    done
    log "All worker nodes have joined the cluster."
}

install_metallb() {
    log "Installing MetalLB..."
    kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.8/config/manifests/metallb-native.yaml
    show_progress 60
    kubectl wait --namespace metallb-system --for=condition=Ready pod -l component=controller --timeout=600s
    kubectl apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: first-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.90.240-192.168.90.250
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: myl2adv
  namespace: metallb-system
EOF
    log "MetalLB installed and configured."
}

install_istio() {
echo -n "Do you want to install Istio? (yes/no) [default: yes]: "
read -r install_istio
install_istio=${install_istio:-yes}  # Default to 'yes' if nothing is entered

if [[ "$install_istio" == "yes" ]]; then
        curl -L https://istio.io/downloadIstio | sh -
        ISTIO_DIR=$(ls -d istio-*)
        sudo mv $ISTIO_DIR/bin/istioctl /usr/local/bin/
        istioctl install --set profile=demo -y
        log "Istio installed."
    else
        log "Skipping Istio installation."
    fi
}

# Main Script
VERBOSE=1  # Set to 0 for silent mode
check_ssh_connection
for node in "${WNODE[@]}" "$MNODE"; do
    setup_containerd "$node"
done


setup_master_node
install_weave
join_worker_nodes
install_csi_longhorn
install_metallb
install_istio

echo "Kubernetes cluster setup completed successfully!"
