# aws-terraform-vpn

Terraform stack for a single-instance OpenVPN server on EC2 behind an Auto Scaling Group.

What this creates:

- AWS provider pinned to `ap-southeast-1` by default.
- Amazon Linux 2023 `arm64` AMI selection for Graviton instances.
- A VPC in Singapore using the AWS IA VPC module.
- Public subnets only, with one EC2 instance maintained by an ASG.
- Default instance type of `t4g.small`.
- An IAM instance profile for Systems Manager and SSM Parameter Store reads.
- A userdata bootstrap that installs OpenVPN on Amazon Linux 2023, enables `amazon-ssm-agent`, mounts a dedicated EBS volume at `/var/lib/openvpn`, and updates `vpn.gynx.cc` in Cloudflare on every boot.

Usage:

1. Copy `terraform.tfvars.example` to `terraform.tfvars` and set `cloudflare_zone_id` and `cloudflare_api_token`.
2. Run `terraform init`.
3. Run `terraform apply`.

OpenVPN persistence:

- Persist your generated OpenVPN material under `/var/lib/openvpn`.
- Put the server config at `/var/lib/openvpn/config/server.conf`.
- Keep your CA, server keys, client keys, CCD, and related PKI under `/var/lib/openvpn/pki`, `/var/lib/openvpn/ccd`, and `/var/lib/openvpn/clients`.
- On boot, `openvpn-bootstrap.service` restores `/var/lib/openvpn/config/server.conf` to `/etc/openvpn/server/server.conf` and starts `openvpn-server@server.service` if the config exists.

Cloudflare boot-time DNS update:

- The instance reads the token from `/infra/vpn/cloudflare/api-token` and the zone ID from `/infra/vpn/cloudflare/zone-id` by default.
- Both SSM paths are configurable through Terraform variables if you want a different hierarchy.
- `update-vpn-dns.service` runs on every boot, discovers the current public IP, and creates or updates the `A` record for `vpn.gynx.cc`.
