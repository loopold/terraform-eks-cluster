variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "external_domain" {
  description = "Domain for the account"
  default     = "k8s.test.devopsvelocity.com"
}

variable "environment" {
  description = "High-level tag for all resources"
  default     = "stg"
}

variable "create_rds" {
  description = "If set to true, create RDS"
  type        = bool
  default     = false
}

variable "db_password" {
  description = "RDS root user password"
  type        = string
  sensitive   = true
}
