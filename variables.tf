variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "ap-southeast-1"
}

variable "name" {
  description = "Base name used for resources."
  type        = string
  default     = "vpn"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.42.0.0/16"
}

variable "az_count" {
  description = "Number of AZs for the VPC module."
  type        = number
  default     = 2
}

variable "instance_type" {
  description = "EC2 instance type for the OpenVPN server."
  type        = string
  default     = "t4g.small"
}

variable "vpn_record_name" {
  description = "Cloudflare DNS record to manage."
  type        = string
  default     = "vpn.gynx.cc"
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for the DNS record."
  type        = string
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token with DNS edit permissions for the zone."
  type        = string
  sensitive   = true
}

variable "cloudflare_api_token_ssm_path" {
  description = "SSM parameter path for the Cloudflare API token."
  type        = string
  default     = "/infra/vpn/cloudflare/api-token"
}

variable "cloudflare_zone_id_ssm_path" {
  description = "SSM parameter path for the Cloudflare zone ID."
  type        = string
  default     = "/infra/vpn/cloudflare/zone-id"
}

variable "cloudflare_record_ttl" {
  description = "Cloudflare DNS TTL. Use 1 for automatic."
  type        = number
  default     = 60
}

variable "openvpn_udp_port" {
  description = "UDP port for OpenVPN."
  type        = number
  default     = 1194
}

variable "openvpn_state_volume_size" {
  description = "Size in GiB for the EBS volume used to persist OpenVPN material."
  type        = number
  default     = 20
}

variable "openvpn_state_device_name" {
  description = "Device name for the persistent OpenVPN state volume."
  type        = string
  default     = "/dev/sdf"
}

variable "ssh_ingress_cidrs" {
  description = "Optional SSH ingress CIDRs. Leave empty to rely on SSM only."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags for created resources."
  type        = map(string)
  default = {
    REPO    = "aws-terraform-vpn"
    CREATOR = "bear"
  }
}
