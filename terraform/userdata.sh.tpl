#!/bin/bash

# Use the public IP address passed as a variable
public_ip=${public_ip}

echo "Starting installation: $(date)"

# Basic system configuration
echo "Configuring hostname and /etc/hosts"
sudo hostnamectl set-hostname securelinedemo
sudo sh -c 'echo "$(hostname -I | awk "{print \$1}") securelinedemo" >> /etc/hosts'
sudo sh -c "echo \"${public_ip} securelinearecord.demodomain.co\" >> /etc/hosts"

# System preparation
echo "Preparing system for Kubernetes"
sudo swapoff -a
sudo modprobe br_netfilter
echo br_netfilter | sudo tee /etc/modules-load.d/kubernetes.conf

# Update sysctl settings all at once
echo "Updating sysctl settings"
cat <<EOF | sudo tee -a /etc/sysctl.conf
net.ipv4.ip_forward=1
vm.max_map_count=262144
EOF
sudo sysctl -p

# Parallel dependency installations
echo "Installing dependencies in parallel"
sudo apt-get update -y
sudo apt-get install -y unzip git

# Install packages in a single command to reduce apt operations
sudo apt-get install -y ca-certificates curl gnupg lsb-release jq python3-pip apt-transport-https

# Set up repositories in parallel
echo "Setting up repositories"
(
  # Docker repository
  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
) &

(
  # Kubernetes repository
  sudo sh -c 'curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg'
  echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
) &

(
  # Helm repository
  curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
) &

(
  # Azure CLI installation
  curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
) &

# Wait for all background processes to complete
wait

# Update package lists
sudo apt-get update -y

# Install all required packages at once
echo "Installing Docker, Kubernetes, and Helm packages"
sudo apt-get install -y containerd.io docker-ce docker-ce-cli docker-buildx-plugin docker-compose-plugin kubeadm kubectl kubelet helm

# Configure containerd
echo "Configuring containerd"
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd

# Install docker-compose standalone if needed
echo "Installing docker-compose (standalone version)"
sudo usermod -aG docker ubuntu
sudo curl -L "https://github.com/docker/compose/releases/download/v2.24.6/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose


# Initialize Kubernetes
echo "Initializing Kubernetes master"
sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --control-plane-endpoint securelinearecord.demodomain.co:6443 --v=5

# Configure kubectl for the current user
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown ubuntu:ubuntu $HOME/.kube/config

# Deploy Flannel CNI network plugin
echo "Deploying Flannel CNI"
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

# Allow scheduling on control-plane node
echo "Removing control-plane taint to allow workloads on master"
kubectl taint nodes --all node-role.kubernetes.io/control-plane-

# Check if the cluster is ready
echo "Waiting for cluster to be ready"
TIMEOUT=300  # 5 minutes timeout
ELAPSED=0
INTERVAL=10  # Check every 10 seconds

while [ $ELAPSED -lt $TIMEOUT ]; do
  if [ $(kubectl get nodes --no-headers | grep -c "NotReady") -eq 0 ]; then
    echo "All nodes are ready!"
    break
  fi
  echo "Not all nodes are ready. Waiting... ($ELAPSED/$TIMEOUT seconds)"
  sleep $INTERVAL
  ELAPSED=$((ELAPSED + INTERVAL))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
  echo "Warning: Timeout reached waiting for nodes to be ready"
fi

# Display final status
echo "Installation completed at: $(date)"
echo "Kubernetes cluster status:"
kubectl get nodes
kubectl get pods -A

# Verify Docker and docker-compose installation
echo "Docker version:"
docker --version
echo "Docker Compose version:"
docker compose version
echo "Docker Compose standalone version:"
docker-compose --version