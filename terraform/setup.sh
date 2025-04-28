#!/bin/bash

HOSTNAME="securelinedemo"
KEY_VAULT_NAME="Securelinesecrets"

echo "Starting setup process: $(date)"

# Setup directories and config upfront
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown ubuntu:ubuntu $HOME/.kube/config


# Azure Login
echo "Logging into Azure using service principal "
az login --service-principal -u "$CLIENT_ID" -p "$CLIENT_SECRET" --tenant "$TENANT_ID"
az account set --subscription "$subscriptionid"

# Start dependency installations in parallel
  echo "Installing dependencies"
  sudo apt-get update -y
  sudo apt-get install -y maven xmlstarlet 

(
  # Install OpenJDK 21 in parallel
  echo "Installing OpenJDK 21"
  sudo apt-get install -y openjdk-21-jdk
  echo 'export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64' >> ~/.bashrc
  echo 'export PATH=$JAVA_HOME/bin:$PATH' >> ~/.bashrc
) &


# Install Azure DevOps agent in parallel
(
  echo "Installing Azure DevOps agent"
  cd /home/ubuntu/
  wget -q https://vstsagentpackage.azureedge.net/agent/4.252.0/vsts-agent-linux-x64-4.252.0.tar.gz
  tar zxf vsts-agent-linux-x64-4.252.0.tar.gz
) &

# Wait for these parallel installations to complete
echo "Waiting for tool installations to complete..."
wait


# Set up key vault policy using service principal
az keyvault set-policy --name $KEY_VAULT_NAME --spn $CLIENT_ID --secret-permissions get set

# Fetch secrets from Azure Key Vault
sonarqubepassword=$(az keyvault secret show --name sonarqubepassword --vault-name $KEY_VAULT_NAME --query value -o tsv)
sonarpostgresqlUsername=$(az keyvault secret show --name sonarpostgresqlUsername --vault-name $KEY_VAULT_NAME --query value -o tsv)
sonarpostgresqlPassword=$(az keyvault secret show --name sonarpostgresqlPassword --vault-name $KEY_VAULT_NAME --query value -o tsv)
sonarpostgresqlDatabase=$(az keyvault secret show --name sonarpostgresqlDatabase --vault-name $KEY_VAULT_NAME --query value -o tsv)
pattoken=$(az keyvault secret show --name pattoken --vault-name $KEY_VAULT_NAME --query value -o tsv)

# Set Public Domain in KeyVault
az keyvault secret set --vault-name $KEY_VAULT_NAME --name "Domain" --value "$PUBLIC_IP"
Domain=$(az keyvault secret show --name Domain --vault-name $KEY_VAULT_NAME --query value -o tsv)

# Wait for all background installations to complete
echo "Waiting for background installations to complete..."
wait

# Source the bashrc to get Java environment variables
source ~/.bashrc

# Configure Azure DevOps agent
echo "Configuring Azure DevOps agent"
cd /home/ubuntu
bash config.sh --unattended --url https://dev.azure.com/Afour-technology --auth pat --token $pattoken --agent $HOSTNAME --pool default --replace --acceptTeeEula

# Start the Azure DevOps agent
sudo /home/ubuntu/svc.sh install
sudo /home/ubuntu/svc.sh start

# Update configuration files with secrets
echo "Updating configuration files"
sed -i "s/\$sonarqubepassword/$sonarqubepassword/g; s/\$postgresqlPassword/$sonarpostgresqlPassword/g; s/\$postgresqlUsername/$sonarpostgresqlUsername/g; s/\$postgresqlDatabase/$sonarpostgresqlDatabase/g" /home/ubuntu/sonarqubevalues.yaml

# Install Helm charts in parallel
echo "Deploying SonarQube"

# Setup Helm repositories
helm repo add sonarqube https://SonarSource.github.io/helm-chart-sonarqube &
wait
helm repo update

# Create namespaces
kubectl create namespace sonarqube

# Deploy SonarQube
helm upgrade --install -n sonarqube sonarqube sonarqube/sonarqube --values /home/ubuntu/sonarqubevalues.yaml

echo "Waiting for pods to be ready..."
# More efficient pod readiness check with timeout
TIMEOUT=600  # 10 minutes
start_time=$(date +%s)
while true; do
  current_time=$(date +%s)
  elapsed=$((current_time - start_time))
  
  if [ $elapsed -gt $TIMEOUT ]; then
    echo "Timeout waiting for pods. Proceeding anyway..."
    break
  fi
  
  not_ready=$(kubectl get pods -A -o jsonpath='{.items[?(@.status.phase!="Running")].metadata.name}')
  if [ -z "$not_ready" ]; then
    echo "All pods are running!"
    break
  fi
  
  echo "Waiting for pods to be ready... (${elapsed}s / ${TIMEOUT}s)"
  sleep 10
done

# Add a sleep to ensure services are fully initialized
echo "Giving services time to initialize..."
sleep 60

# Verify SonarQube is responding before creating tokens
echo "Waiting for SonarQube to be accessible..."
max_attempts=20
attempt=1
while [ $attempt -le $max_attempts ]; do
  if curl -s -o /dev/null -w "%{http_code}" "http://$Domain:30000"; then
    echo "SonarQube is accessible!"
    break
  fi
  echo "Waiting for SonarQube to be accessible (attempt $attempt/$max_attempts)..."
  sleep 15
  attempt=$((attempt+1))
done

# Create SonarQube tokens in parallel
echo "Creating SonarQube tokens"
(
  sleep 30  # Brief pause to ensure SonarQube is accessible
  sonartoken=$(curl -s -u admin:$sonarqubepassword -X POST "http://$Domain:30000/api/user_tokens/generate" -d "name=security" -d "type=GLOBAL_ANALYSIS_TOKEN" | grep -o '"token":"[^"]*"' | cut -d':' -f2 | tr -d '"')
  az keyvault secret set --vault-name $KEY_VAULT_NAME --name "sonartoken" --value "$sonartoken"
  
  # Create SonarQube project
  curl -s -u admin:$sonarqubepassword -X POST "http://$Domain:30000/api/projects/create" -d "name=SecureLine" -d "project=securityproject"
  
  # Create SonarQube user token
  sonarusertoken=$(curl -s -u admin:$sonarqubepassword -X POST "http://$Domain:30000/api/user_tokens/generate" -d "name=Securelineuser" | grep -o '"token":"[^"]*' | cut -d'"' -f4)
  az keyvault secret set --vault-name $KEY_VAULT_NAME --name "Sonarqubeusertoken" --value "$sonarusertoken"
) &

# Wait for services to be configured
wait

echo "Setup completed successfully: $(date)"