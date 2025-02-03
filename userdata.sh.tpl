#!/bin/bash

echo "Set hostname"
sudo hostnamectl set-hostname master

echo "########################################################################"

echo  " Update /etc/hosts with local IP and new hostname"
sudo sh -c 'echo "$(hostname -I | awk "{print \$1}") master" >> /etc/hosts'

echo "########################################################################"

echo "Disable swap"
sudo swapoff -a

echo "########################################################################"

echo "Load br_netfilter module"
sudo modprobe br_netfilter
echo br_netfilter | sudo tee /etc/modules-load.d/kubernetes.conf

echo "########################################################################"

echo "Update and install prerequisites"
sudo apt update -y
sudo apt install -y ca-certificates curl gnupg lsb-release  jq python3-pip
pip install selenium
wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb && sudo dpkg -i google-chrome-stable_current_amd64.deb || sudo apt -f install -y
#sudo pip3 install https://s3.amazonaws.com/cloudformation-examples/aws-cfn-bootstrap-py3-latest.tar.gz
#sudo ln -s /usr/local/init/ubuntu/cfn-hup /etc/init.d/cfn-hup


echo "########################################################################"


echo "Install AzureCli"
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash


echo "########################################################################"


echo "Configure Docker repository"
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update -y
sudo apt install -y containerd.io
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo service containerd restart

echo "########################################################################"


echo "Configure Kubernetes repository"
sudo sh -c 'curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg'
sudo apt update -y
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt update -y
sudo apt install -y kubeadm kubectl kubelet

echo "########################################################################"


echo  "install helm"
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
sudo apt-get install apt-transport-https --yes
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt update -y
sudo apt-get install helm -y

echo "########################################################################"


echo "Edit sysctl.conf"

echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

echo "########################################################################"


echo "Initialize Kubernetes master"
sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --control-plane-endpoint securelinearecord.demodomain.co:6443
echo "sleeping1 30sec"
sleep 30s

echo "########################################################################"


echo "Configure kubectl for the current user"

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown ubuntu:ubuntu $HOME/.kube/config
echo "sleeping2 30sec"

echo "########################################################################"

echo "Deploy Flannel CNI"
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

echo "########################################################################"


echo "Display nodes and pods"
kubectl get nodes
kubectl get pods -n kube-system

echo "########################################################################"


echo "Taint nodes to mark the master as a control plane node"
kubectl taint nodes --all node-role.kubernetes.io/control-plane-

echo "########################################################################"


#echo  "cp k8s config to s3 bucket"
#aws s3 cp /home/ubuntu/.kube/config s3://securelineartifacts/k8sconf/

echo "########################################################################"


echo  "check if the cluster is ready"
while [[ $(kubectl get nodes --no-headers | awk '{print $2}' | grep -c "NotReady") -gt 0 ]]; do echo "Not all nodes are ready. Waiting..."; sleep 5; done && echo "All nodes are ready!"

echo "########################################################################"


} > script_output.txt 2>&1