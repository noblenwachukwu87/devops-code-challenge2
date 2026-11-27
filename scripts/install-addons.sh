#!/usr/bin/env bash
# Installs cluster add-ons after `terraform apply`.
# IAM comes from EKS Pod Identity (terraform/modules/addon-iam), so no eksctl or service account annotations.
set -euo pipefail

REGION="us-east-1"
CLUSTER_NAME="$(terraform -chdir=terraform output -raw cluster_name)"
VPC_ID="$(terraform -chdir=terraform output -raw vpc_id)"

echo "==> Pointing kubectl at ${CLUSTER_NAME}"
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME"

echo "==> Adding Helm repos"
helm repo add eks https://aws.github.io/eks-charts
helm repo add autoscaler https://kubernetes.github.io/autoscaler
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo update

echo "==> AWS Load Balancer Controller"
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --version 3.7.0 \
  --namespace kube-system \
  --set clusterName="$CLUSTER_NAME" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region="$REGION" \
  --set vpcId="$VPC_ID" \
  --wait

echo "==> metrics-server"
helm upgrade --install metrics-server metrics-server/metrics-server \
  --version 3.14.0 \
  --namespace kube-system \
  --wait

echo "==> Cluster Autoscaler (image pinned to match Kubernetes 1.36)"
helm upgrade --install cluster-autoscaler autoscaler/cluster-autoscaler \
  --version 9.60.1 \
  --namespace kube-system \
  --set autoDiscovery.clusterName="$CLUSTER_NAME" \
  --set awsRegion="$REGION" \
  --set rbac.serviceAccount.name=cluster-autoscaler \
  --set image.tag=v1.36.0 \
  --wait
  
echo "==> Done. Add-on pods:"
kubectl get pods -n kube-system