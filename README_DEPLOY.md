# Deploy Guide (EKS + Terraform + Helm)

1) Terraform
```
cd infra/terraform
terraform init
terraform apply -auto-approve  -var='db_password=ChangeMeStrong!'
aws eks update-kubeconfig --region us-east-1 --name $(terraform output -raw cluster_name)
```

2) AWS Load Balancer Controller (required for ALB Ingress)
```
helm repo add eks https://aws.github.io/eks-charts
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller   -n kube-system   --set clusterName=$(terraform -chdir=infra/terraform output -raw cluster_name)   --set serviceAccount.create=true   --set region=$(terraform -chdir=infra/terraform output -raw aws_region)   --set vpcId=$(terraform -chdir=infra/terraform output -raw vpc_id)
```

3) Helm deploy
```
helm upgrade --install statuspage infra/helm/statuspage   -n statuspage --create-namespace   --set image.repository=$(terraform -chdir=infra/terraform output -raw ecr_repo_url)   --set image.tag=latest   --set env.SECRET_KEY=change-me   --set env.DATABASE_URL='postgres://statuspage:PASS@HOST:5432/statuspage'   --set ingress.hosts[0].host='status.example.com'   --set acmArn=$(terraform -chdir=infra/terraform output -raw acm_arn)
```

4) GitHub Actions – set repo secrets:
`AWS_ROLE_ARN, ECR_REPO, EKS_CLUSTER, SECRET_KEY, DATABASE_URL, REDIS_URL, STATUS_HOSTNAME, ACM_ARN`
