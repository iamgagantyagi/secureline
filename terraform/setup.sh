#!/bin/bash

HOSTNAME="securelinedemo"
KEY_VAULT_NAME="Securelinevault1"
MSI_ID="013ce2ba-1776-4665-8000-b84fcb4606f6"

echo "Starting setup process: $(date)"

# Setup directories and config upfront
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown ubuntu:ubuntu $HOME/.kube/config

# Azure Key Vault login and setup
echo "Logging into Azure using managed identity"
az login --identity --username $MSI_ID &

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

# Wait for these parallel installations to complete
echo "Waiting for tool installations to complete..."
wait

# Set up key vault policy
az keyvault set-policy --name $KEY_VAULT_NAME --spn $MSI_ID --secret-permissions get set

# Fetch secrets from Azure Key Vault
sonarqubepassword=$(az keyvault secret show --name sonarqubepassword --vault-name $KEY_VAULT_NAME --query value -o tsv)
postgresqlUsername=$(az keyvault secret show --name postgresqlUsername --vault-name $KEY_VAULT_NAME --query value -o tsv)
postgresqlPassword=$(az keyvault secret show --name postgresqlPassword --vault-name $KEY_VAULT_NAME --query value -o tsv)
postgresqlDatabase=$(az keyvault secret show --name postgresqlDatabase --vault-name $KEY_VAULT_NAME --query value -o tsv)
defectdojopostgresqlUsername=$(az keyvault secret show --name defectdojopostgresqlUsername --vault-name $KEY_VAULT_NAME --query value -o tsv)
defectdojopostgresqlPassword=$(az keyvault secret show --name defectdojopostgresqlPassword --vault-name $KEY_VAULT_NAME --query value -o tsv)
defectdojoUIPassword=$(az keyvault secret show --name defectdojoUIPassword --vault-name $KEY_VAULT_NAME --query value -o tsv)
defectdojodatabase=$(az keyvault secret show --name defectdojodatabase --vault-name $KEY_VAULT_NAME --query value -o tsv)
rabbitmqpassword=$(az keyvault secret show --name rabbitmqpassword --vault-name $KEY_VAULT_NAME --query value -o tsv)
pattoken=$(az keyvault secret show --name pattoken --vault-name $KEY_VAULT_NAME --query value -o tsv)

# Set DefectDojoDomain in KeyVault
az keyvault secret set --vault-name $KEY_VAULT_NAME --name "DefectDojoDomain" --value "$PUBLIC_IP"
DefectDojoDomain=$(az keyvault secret show --name DefectDojoDomain --vault-name $KEY_VAULT_NAME --query value -o tsv)

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
sed -i "s/\$sonarqubepassword/$sonarqubepassword/g; s/\$postgresqlPassword/$postgresqlPassword/g; s/\$postgresqlUsername/$postgresqlUsername/g; s/\$postgresqlDatabase/$postgresqlDatabase/g" /home/ubuntu/values.yaml
sed -i "s/\$defectdojoUIPassword/$defectdojoUIPassword/g; s/\$defectdojopostgresqlUsername/$defectdojopostgresqlUsername/g; s/\$defectdojopostgresqlPassword/$defectdojopostgresqlPassword/g; s/\$defectdojodatabase/$defectdojodatabase/g; s/\$rabbitmqpassword/$rabbitmqpassword/g; s/\$DefectDojoDomain/$DefectDojoDomain/g" /home/ubuntu/defectdojo.yaml

# Install Helm charts in parallel
echo "Deploying SonarQube and DefectDojo"

# Setup Helm repositories
helm repo add sonarqube https://SonarSource.github.io/helm-chart-sonarqube &
helm repo add defectdojo 'https://raw.githubusercontent.com/DefectDojo/django-DefectDojo/helm-charts' &
wait
helm repo update

# Create namespaces
kubectl create namespace sonarqube
kubectl create namespace defectdojo

# Deploy SonarQube and DefectDojo
helm upgrade --install -n sonarqube sonarqube sonarqube/sonarqube --values /home/ubuntu/values.yaml
helm upgrade --install -n defectdojo defectdojo defectdojo/defectdojo --values /home/ubuntu/defectdojo.yaml --version 1.6.134 


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

# Patch DefectDojo service for NodePort
echo "Configuring DefectDojo NodePort"
kubectl patch svc defectdojo-django -n defectdojo -p '{"spec": {"type": "NodePort", "ports": [{"port": 80, "nodePort": 30001, "protocol": "TCP"}]}}' &

# Verify SonarQube is responding before creating tokens
echo "Waiting for SonarQube to be accessible..."
max_attempts=20
attempt=1
while [ $attempt -le $max_attempts ]; do
  if curl -s -o /dev/null -w "%{http_code}" "http://$DefectDojoDomain:30000"; then
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
  token=$(curl -s -u admin:$sonarqubepassword -X POST "http://$DefectDojoDomain:30000/api/user_tokens/generate" -d "name=security" -d "type=GLOBAL_ANALYSIS_TOKEN" | grep -o '"token":"[^"]*"' | cut -d':' -f2 | tr -d '"')
  az keyvault secret set --vault-name $KEY_VAULT_NAME --name "Sonartoken" --value "$token"
  
  # Create SonarQube project
  curl -s -u admin:$sonarqubepassword -X POST "http://$DefectDojoDomain:30000/api/projects/create" -d "name=SecureLine" -d "project=securityproject"
  
  # Create SonarQube user token
  usertoken=$(curl -s -u admin:$sonarqubepassword -X POST "http://$DefectDojoDomain:30000/api/user_tokens/generate" -d "name=Securelineuser" | grep -o '"token":"[^"]*' | cut -d'"' -f4)
  az keyvault secret set --vault-name $KEY_VAULT_NAME --name "Sonarqubeusertoken" --value "$usertoken"
) &

# Wait for services to be configured
wait

# Export secrets as environment variables for dd.py
export SONARQUBE_PASSWORD="$sonarqubepassword"
export DEFECTDOJO_PASSWORD="$defectdojoUIPassword"
export DEFECTDOJO_DOMAIN="$DefectDojoDomain" 

# Get DefectDojo token and create configurations
echo "Configuring DefectDojo"
defectdojotoken=$(curl -s -X POST -H 'content-type: application/json' http://$DefectDojoDomain:30001/api/v2/api-token-auth/ -d '{"username": "admin", "password": "'$defectdojoUIPassword'"}' | awk -F'"' '{print $4}')

# Store token in KeyVault
az keyvault secret set --vault-name $KEY_VAULT_NAME --name "defectdojotoken" --value "$defectdojotoken"

# Create DefectDojo configurations in parallel
(
  # Create product
  product_id=$(curl -s -X POST 'http://'$DefectDojoDomain':30001/api/v2/products/' -H 'accept: application/json' -H 'Content-Type: application/json' -H 'Authorization: Token '$defectdojotoken'' -d '{"tags": ["SecureLine"], "name": "SecureLine", "description": "SecureLine Security", "enable_full_risk_acceptance": true, "prod_type": 1}' | jq -r '.id')
  
  # Create engagement
  curl -s -X POST 'http://'$DefectDojoDomain':30001/api/v2/engagements/' -H 'accept: application/json' -H 'Content-Type: application/json' -H 'Authorization: Token '$defectdojotoken'' -d '{"name": "SecureLine", "description": "SecureLine Engagement", "target_start": "'$(date +%F)'", "target_end": "'$(date -d "$(date +%F) +60 days" +%F)'", "product": '$product_id'}'
) &

(
  # Create tool configuration
  curl -s -X 'POST' 'http://'$DefectDojoDomain':30001/api/v2/tool_configurations/' -H 'accept: application/json' -H 'Content-Type: application/json' -H 'Authorization: Token '$defectdojotoken'' -d '{"name": "sonarqube", "url": "http://'$DefectDojoDomain':30000/api", "authentication_type": "Password", "username": "admin", "password": "'$sonarqubepassword'", "tool_type": 6}'
  
  # Run DefectDojo setup script if it exists
  if [ -f /home/ubuntu/dd.py ]; then
    sudo chmod +x /home/ubuntu/dd.py
    python3 /home/ubuntu/dd.py
  fi
) &

# Wait for all background operations to complete
wait

# Create product API scan configuration (must be done after other configs are created)
curl -s -X 'POST' 'http://'$DefectDojoDomain':30001/api/v2/product_api_scan_configurations/' -H 'accept: application/json' -H 'Content-Type: application/json' -H 'Authorization: Token '$defectdojotoken'' -d '{ "service_key_1": "SecureLine", "product": 1, "tool_configuration": 1}'

echo "Setup completed successfully: $(date)"