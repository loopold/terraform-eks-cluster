variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "external_domain" {
  description = "Domain for the account"
  default     = "k8s.test.devopsvelocity.com"
}
