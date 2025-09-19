#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------
# Sync Terraform outputs + AWS Secrets Manager into GitHub secrets
# Must be run from inside infra/terraform/ after `terraform apply`
# ---------------------------------------------------------------

# ------------------- FETCH TERRAFORM OUTPUTS -------------------
SECRET_KEY=$(terraform output -raw secret_key)
AWS_REGION=$(terraform output -raw aws_region)
ROLE_ARN=$(terraform output -raw github_deploy_role_arn)
ECR_REPO=$(terraform output -raw ecr_repo_url)
EKS_CLUSTER=$(terraform output -raw cluster_name)
STATUS_HOSTNAME=$(terraform output -raw static_bucket_name)   # replace with Route53 output later

DB_HOST=$(terraform output -raw db_host)
DB_PORT=$(terraform output -raw db_port)
DB_NAME=$(terraform output -raw db_name)
DB_USER=$(terraform output -raw db_username)

# ------------------- FETCH RDS PASSWORD FROM SECRETS MANAGER -------------------
DBID=status-page-ay-pg   # adjust if your DB identifier differs

SECRET_ARN=$(aws rds describe-db-instances \
  --region "$AWS_REGION" \
  --db-instance-identifier "$DBID" \
  --query 'DBInstances[0].MasterUserSecret.SecretArn' \
  --output text)

DB_SECRET=$(aws secretsmanager get-secret-value \
  --region "$AWS_REGION" \
  --secret-id "$SECRET_ARN" \
  --query SecretString \
  --output text)

DB_PASS=$(echo "$DB_SECRET" | jq -r .password)

DATABASE_URL="postgresql://${DB_USER}:${DB_PASS}@${DB_HOST}:${DB_PORT}/${DB_NAME}?sslmode=require"

# ------------------- PUSH SECRETS TO GITHUB -------------------
gh secret set AWS_REGION       --body "$AWS_REGION"
gh secret set AWS_ROLE_ARN     --body "$ROLE_ARN"
gh secret set ECR_REPO         --body "$ECR_REPO"
gh secret set EKS_CLUSTER      --body "$EKS_CLUSTER"
gh secret set SECRET_KEY       --body "$SECRET_KEY"
gh secret set DATABASE_URL     --body "$DATABASE_URL"
gh secret set STATUS_HOSTNAME  --body "$STATUS_HOSTNAME"

echo " GitHub secrets updated successfully."