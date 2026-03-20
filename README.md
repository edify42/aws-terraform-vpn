# aws-terraform-vpn

Terraform stack for a single-instance OpenVPN server on EC2 behind an Auto Scaling Group.

What this creates:

- AWS provider pinned to `ap-southeast-1` by default.
- Amazon Linux 2023 `arm64` AMI selection for Graviton instances.
- A VPC in Singapore using the AWS IA VPC module.
- Public subnets only, with one EC2 instance maintained by an ASG.
- Default instance type of `t4g.small`.
- An IAM instance profile for Systems Manager and SSM Parameter Store reads.
- A versioned private S3 bucket for the OpenVPN config bundle.
- A userdata bootstrap that installs OpenVPN on Amazon Linux 2023, enables `amazon-ssm-agent`, syncs config from S3 into `/var/lib/openvpn` on the root filesystem, and updates `vpn.gynx.cc` in Cloudflare on every boot.

Usage:

1. Create the Cloudflare SSM parameters yourself before applying:
   - `/infra/vpn/cloudflare/api-token` as a `SecureString`
   - `/infra/vpn/cloudflare/zone-id` as a `String`
2. Copy `terraform.tfvars.example` to `terraform.tfvars` only if you want to override the default SSM paths.
3. Run `terraform init`.
4. Run `terraform apply`.

OpenVPN config delivery:

- Upload your OpenVPN bundle to `s3://<openvpn_config_bucket_name>/<openvpn_config_s3_prefix>/`.
- Put the server config at `config/server.conf` within that prefix.
- Keep your CA, server keys, client keys, CCD, and related PKI under `pki/`, `ccd/`, and `clients/` within that prefix.
- On boot, `openvpn-bootstrap.service` syncs the S3 prefix to `/var/lib/openvpn`, restores `/var/lib/openvpn/config/server.conf` to `/etc/openvpn/server/server.conf`, and starts `openvpn-server@server.service` if the config exists.

Cloudflare boot-time DNS update:

- The instance reads the token from `/infra/vpn/cloudflare/api-token` and the zone ID from `/infra/vpn/cloudflare/zone-id` by default.
- Both SSM paths are configurable through Terraform variables if you want a different hierarchy.
- `update-vpn-dns.service` runs on every boot, discovers the current public IP, and creates or updates the `A` record for `vpn.gynx.cc`.
