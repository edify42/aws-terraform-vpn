output "vpc_id" {
  description = "Created VPC ID."
  value       = module.vpc.vpc_attributes.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs used by the ASG."
  value = [
    for _, subnet in module.vpc.public_subnet_attributes_by_az : subnet.id
  ]
}

output "autoscaling_group_name" {
  description = "Auto Scaling Group name."
  value       = aws_autoscaling_group.vpn.name
}

output "launch_template_id" {
  description = "Launch template ID."
  value       = aws_launch_template.vpn.id
}

output "instance_profile_name" {
  description = "IAM instance profile name."
  value       = aws_iam_instance_profile.instance.name
}

output "cloudflare_api_token_ssm_path" {
  description = "SSM parameter path holding the Cloudflare API token."
  value       = var.cloudflare_api_token_ssm_path
}

output "cloudflare_zone_id_ssm_path" {
  description = "SSM parameter path holding the Cloudflare zone ID."
  value       = var.cloudflare_zone_id_ssm_path
}

output "openvpn_data_path" {
  description = "Instance path used for the synced OpenVPN config, keys, and PKI."
  value       = "/var/lib/openvpn"
}

output "openvpn_config_bucket_name" {
  description = "S3 bucket used to store the OpenVPN config bundle."
  value       = aws_s3_bucket.openvpn_config.bucket
}

output "openvpn_config_s3_prefix" {
  description = "S3 prefix used to sync the OpenVPN config bundle to the instance."
  value       = local.openvpn_config_s3_prefix
}
