#!/bin/bash

HOSTNAME="securelinedemo"

# Create .kube directory and configure kubectl
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown ubuntu:ubuntu $HOME/.kube/config

# Azure Key Vault setup (replace with your Key Vault name)
az login --identity --username 013ce2ba-1776-4665-8000-b84fcb4606f6

az keyvault set-policy --name Securelinevault1 --spn 013ce2ba-1776-4665-8000-b84fcb4606f6 --secret-permissions get set

KEY_VAULT_NAME="Securelinevault1"


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
defectdojodomain=$(az keyvault secret show --name defectdojodomain --vault-name $KEY_VAULT_NAME --query value -o tsv)
pattoken=$(az keyvault secret show --name pattoken --vault-name $KEY_VAULT_NAME --query value -o tsv)

# Install dependencies
sudo apt update -y
sudo apt install -y curl git

# Install Azure DevOps self-hosted runner
wget https://vstsagentpackage.azureedge.net/agent/4.252.0/vsts-agent-linux-x64-4.252.0.tar.gz
tar zxvf vsts-agent-linux-x64-4.252.0.tar.gz
bash config.sh --unattended --url https://dev.azure.com/Afour-technology --auth pat --token $pattoken --agent $HOSTNAME --pool default --acceptTeeEula

# Start the runner
bash run.sh

# Download configuration files
#wget https://raw.githubusercontent.com/prashantsakharkar/secureline/main/values.yaml -P /home/ubuntu
#wget https://raw.githubusercontent.com/prashantsakharkar/secureline/main/defectdojo_values.yaml -P /home/ubuntu

# Update configuration files with secrets
sed -i "s/\$sonarqubepassword/$sonarqubepassword/g; s/\$postgresqlPassword/$postgresqlPassword/g; s/\$postgresqlUsername/$postgresqlUsername/g; s/\$postgresqlDatabase/$postgresqlDatabase/g" /home/ubuntu/values.yaml
sed -i "s/\$defectdojoUIPassword/$defectdojoUIPassword/g; s/\$defectdojopostgresqlUsername/$defectdojopostgresqlUsername/g; s/\$defectdojopostgresqlPassword/$defectdojopostgresqlPassword/g; s/\$defectdojodatabase/$defectdojodatabase/g; s/\$rabbitmqpassword/$rabbitmqpassword/g; s/\$defectdojodomain/$defectdojodomain/g" /home/ubuntu/defectdojo.yaml

# Deploy SonarQube
helm repo add sonarqube https://SonarSource.github.io/helm-chart-sonarqube
helm repo update
kubectl create namespace sonarqube
helm upgrade --install -n sonarqube sonarqube sonarqube/sonarqube --values /home/ubuntu/values.yaml

# Deploy DefectDojo
helm repo add defectdojo 'https://raw.githubusercontent.com/DefectDojo/django-DefectDojo/helm-charts'
helm repo update
kubectl create namespace defectdojo
helm upgrade --install -n defectdojo defectdojo defectdojo/defectdojo --values /home/ubuntu/defectdojo.yaml --version 1.6.134

# Wait for all pods to be ready
while [ $(kubectl get pods -A --output=jsonpath='{range .items[*]}{.status.containerStatuses[*].ready}{"\n"}{end}' | grep -c -E 'true|false') -ne $(kubectl get pods -A --output=jsonpath='{.items[*].metadata.name}' | wc -w) ]; do
  echo "Waiting for all pods to be ready..."
  sleep 5
done
echo "All pods are ready!"
sleep 30

# Create SonarQube token
token=$(curl -u admin:$sonarqubepassword -X POST "http://$defectdojodomain:30000/api/user_tokens/generate" -d "name=security" -d "type=GLOBAL_ANALYSIS_TOKEN" | grep -o '"token":"[^"]*"' | cut -d':' -f2 | tr -d '"')

# Store SonarQube token in Azure Key Vault
az keyvault secret set --vault-name $KEY_VAULT_NAME --name "sonarsecret" --value "$token"

# Create SonarQube project
curl -u admin:$sonarqubepassword -X POST "http://$defectdojodomain:30000/api/projects/create" -d "name=SecureLine" -d "project=securityproject"

# Create SonarQube user token
usertoken=$(curl -u admin:$sonarqubepassword -X POST "http://$defectdojodomain:30000/api/user_tokens/generate" -d "name=Securelineuser" | grep -o '"token":"[^"]*' | cut -d'"' -f4)

# Store SonarQube user token in Azure Key Vault
az keyvault secret set --vault-name $KEY_VAULT_NAME --name "Sonarqubeusertoken" --value "$usertoken"

# Patch DefectDojo service for NodePort
kubectl patch svc defectdojo-django -n defectdojo -p '{"spec": {"type": "NodePort", "ports": [{"port": 80, "nodePort": 30001, "protocol": "TCP"}]}}'
sleep 10

# Create DefectDojo token
defectdojotoken=$(curl -X POST -H 'content-type: application/json' http://$defectdojodomain:30001/api/v2/api-token-auth/ -d '{"username": "admin", "password": "'$defectdojoUIPassword'"}' | awk -F'"' '{print $4}')
sleep 5

# Store DefectDojo token in Azure Key Vault
az keyvault secret set --vault-name $KEY_VAULT_NAME --name "defectdojosecret" --value "$defectdojotoken"
sleep 5

# Create DefectDojo product
product_id=$(curl -X POST 'http://'$defectdojodomain':30001/api/v2/products/' -H 'accept: application/json' -H 'Content-Type: application/json' -H 'Authorization: Token '$defectdojotoken'' -d '{"tags": ["SecureLine"], "name": "SecureLine", "description": "SecureLine Security", "enable_full_risk_acceptance": true, "prod_type": 1}' | jq -r '.id')
sleep 5

# Create DefectDojo engagement
curl -X POST 'http://'$defectdojodomain':30001/api/v2/engagements/' -H 'accept: application/json' -H 'Content-Type: application/json' -H 'Authorization: Token '$defectdojotoken'' -d '{"name": "SecureLine", "description": "SecureLine Engagement", "target_start": "'$(date +%F)'", "target_end": "'$(date -d "$(date +%F) +60 days" +%F)'", "product": '$product_id'}'
sleep 5

# Create DefectDojo tool configuration
curl -X 'POST' 'http://'$defectdojodomain':30001/api/v2/tool_configurations/' -H 'accept: application/json' -H 'Content-Type: application/json' -H 'Authorization: Token '$defectdojotoken'' -d '{"name": "sonarqube", "url": "http://'$defectdojodomain':30000/api", "authentication_type": "Password", "username": "admin", "password": "'$sonarqubepassword'", "tool_type": 6}'
sleep 5

# Set DefectDojo password
#wget https://raw.githubusercontent.com/prashantsakharkar/secureline/main/dd.py -P /home/ubuntu/
sudo chmod +x /home/ubuntu/dd.py
python3 /home/ubuntu/dd.py
sleep 5

# Create DefectDojo product API scan configuration
curl -X 'POST' 'http://'$defectdojodomain':30001/api/v2/product_api_scan_configurations/' -H 'accept: application/json' -H 'Content-Type: application/json' -H 'Authorization: Token '$defectdojotoken'' -d '{ "service_key_1": "securityproject", "product": 1, "tool_configuration": 1}'

# Clean up
#rm -rf /home/ubuntu/values.yaml
#rm -rf /home/ubuntu/defectdojo.yaml
