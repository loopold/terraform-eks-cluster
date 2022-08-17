# Kubernetes provider
# https://learn.hashicorp.com/terraform/kubernetes/provision-eks-cluster#optional-configure-terraform-kubernetes-provider
# To learn how to schedule deployments and services using the provider, go here: https://learn.hashicorp.com/terraform/kubernetes/deploy-nginx-kubernetes
# The Kubernetes provider is included in this file so the EKS module can complete successfully. Otherwise, it throws an error when creating `kubernetes_config_map.aws_auth`.
# You should **not** schedule deployments and services in this workspace. This keeps workspaces modular (one for provision EKS, another for scheduling Kubernetes resources) as per best practices.
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
}

provider "aws" {
  region = var.region
}

data "aws_availability_zones" "available" {}

locals {
  cluster_name = "education-eks"
  # cluster_name = "education-eks-${random_string.suffix.result}"
}

resource "random_string" "suffix" {
  length  = 8
  special = false
}

data "aws_route53_zone" "this" {
  name         = var.external_domain
  private_zone = false
}

# resource "aws_acm_certificate" "wild" {
#   domain_name               = "*.${var.external_domain}"
#   validation_method         = "DNS"

#   lifecycle {
#     create_before_destroy = true
#   }

#   tags = {
#     Terraform   = "true"
#   }
# }

module "acm" {
  source  = "terraform-aws-modules/acm/aws"
  version = "4.0.1"

  domain_name = var.external_domain
  zone_id     = coalescelist(data.aws_route53_zone.this.*.zone_id)[0]

  subject_alternative_names = [
    "*.${var.external_domain}",
    "alerts.${var.external_domain}",
  ]

  wait_for_validation = true

  tags = {
    Name = var.external_domain
    Terraform   = "true"
  }
}
