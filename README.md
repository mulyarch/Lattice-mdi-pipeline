
# 🛡️ Anduril MDI Sovereign Infrastructure — Multi-Cloud Architecture


> A production-grade, multi-cloud sovereign infrastructure deployment spanning AWS and Azure, designed for mission-critical defense workloads with zero-trust security, encrypted communications, and automated CI/CD pipelines.

---

## 📐 Architecture Overview



---

## 🚀 Key Features

### Multi-Cloud Infrastructure
- **AWS EKS** — Managed Kubernetes (v1.30) across 3 Availability Zones with auto-scaling node groups
- **Azure AKS** — Managed Kubernetes with system and mission node pools
- **Cross-Cloud VPN** — Site-to-site IPsec with IKEv2, AES-256-GCM, and BGP dynamic routing (ASN 64512 ↔ 65515)

### Security & Compliance
- **Encryption at Rest** — AWS KMS (customer-managed CMK) + Azure Key Vault
- **Encryption in Transit** — TLS 1.2+ enforced, IPsec AES-256-GCM tunnels
- **Zero-Trust Networking** — Private subnets, NACLs, Security Groups, NSGs, deny-all defaults
- **Identity & Access** — IRSA (AWS), Workload Identity (Azure), least-privilege pod-level IAM
- **Threat Detection** — GuardDuty, CloudWatch Alarms, SNS Alerts, Azure Defender
- **Instance Hardening** — IMDSv2 enforced, CIS Benchmarks, STIG-aligned

### CI/CD & Automation
- **GitHub Actions** — Automated lint, validate, security scan (tfsec/checkov), plan, and gated apply
- **Environment Promotion** — dev → staging → prod with manual approval gates
- **Ansible Playbooks** — Node hardening, monitoring configuration, VPN provisioning
- **Infrastructure as Code** — 100% Terraform with remote S3 backend and state locking

---

## 📁 Repository Structure



---

## 🛠️ Technology Stack

| Layer | Technology | Purpose |
|-------|-----------|---------|
| **IaC** | Terraform 1.5+ | Infrastructure provisioning |
| **Configuration** | Ansible | Post-deploy hardening & config |
| **Containers** | Kubernetes (EKS/AKS) | Workload orchestration |
| **CI/CD** | GitHub Actions | Automated pipeline |
| **Security Scanning** | tfsec, checkov | IaC security validation |
| **Monitoring** | CloudWatch, Azure Monitor | Observability |
| **Threat Detection** | GuardDuty, Defender | Runtime security |
| **Secrets** | KMS, Key Vault | Encryption key management |
| **Networking** | IPsec VPN, BGP | Cross-cloud connectivity |

---

## 🔐 Security Architecture



---

## ⚡ Quick Start

### Prerequisites
- Terraform >= 1.5
- AWS CLI configured (with appropriate IAM permissions)
- Azure CLI authenticated (`az login`)
- kubectl installed
- GitHub CLI (`gh`) for repository management

### Deploy

```bash
# Clone the repository
git clone https://github.com/yuriymul/anduril-mdi-pipeline.git
cd anduril-mdi-pipeline/terraform

# Initialize Terraform
terraform init

# Plan the deployment
terraform plan -out=deploy.tfplan

# Apply (creates all infrastructure)
terraform apply deploy.tfplan

# Connect to EKS
aws eks update-kubeconfig --name mdi-sovereign-dev --region us-east-1

# Deploy Kubernetes workloads
kubectl apply -f ../kubernetes/

terraform destroy

aws_eks_cluster_name
aws_vpc_id
aws_s3_bucket_name
aws_kms_key_arn
deployment_summary