output "cluster_id" {
  description = "EKS cluster ID"
  value       = module.eks.cluster_id
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group ids attached to the cluster control plane"
  value       = module.eks.cluster_security_group_id
}

output "region" {
  description = "AWS region"
  value       = var.region
}

output "cluster_name" {
  description = "Kubernetes Cluster Name"
  value       = local.cluster_name
}

output "ca" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = module.eks.cluster_certificate_authority_data
}

output "oidc_provider" {
  description = "The OpenID Connect identity provider (issuer URL without leading `https://`)"
  value       = module.eks.oidc_provider
}

output "oidc_provider_arn" {
  description = "The ARN of the OIDC Provider if `enable_irsa = true`"
  value       = module.eks.oidc_provider_arn
}

output "main_region" {
  value = local.main_region
}

output "db_version" {
  description = "RDS instance version"
  value       = var.create_rds ? aws_db_instance.education[0].engine_version : null
}

output "db_hostname" {
  description = "RDS instance hostname"
  value       = var.create_rds ? aws_db_instance.education[0].address : null
  sensitive   = true
}

output "db_port" {
  description = "RDS instance port"
  value       = var.create_rds ? aws_db_instance.education[0].port : null
  sensitive   = true
}

output "db_username" {
  description = "RDS instance root username"
  value       = var.create_rds ? aws_db_instance.education[0].username : null
  sensitive   = true
}
