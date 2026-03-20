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

First-time manual initialization:

1. Install the tooling on a workstation or temporary admin host:
   ```bash
   sudo dnf install -y openvpn easy-rsa awscli
   ```
2. Create a working directory and initialize Easy-RSA:
   ```bash
   mkdir -p ~/openvpn-bootstrap
   cp -r /usr/share/easy-rsa/3 ~/openvpn-bootstrap/easy-rsa
   cd ~/openvpn-bootstrap/easy-rsa
   ./easyrsa init-pki
   ```
3. Create the certificate authority, server certificate, client certificate, DH params, and shared TLS key:
   ```bash
   ./easyrsa build-ca
   ./easyrsa build-server-full server nopass
   ./easyrsa build-client-full client1 nopass
   ./easyrsa gen-dh
   openvpn --genkey secret pki/ta.key
   ```
4. Create the bundle layout expected by the EC2 bootstrap:
   ```bash
   mkdir -p ~/openvpn-bootstrap/bundle/config
   mkdir -p ~/openvpn-bootstrap/bundle/pki/issued
   mkdir -p ~/openvpn-bootstrap/bundle/pki/private
   mkdir -p ~/openvpn-bootstrap/bundle/ccd
   mkdir -p ~/openvpn-bootstrap/bundle/clients
   ```
5. Write the initial server config:
   ```bash
   cat > ~/openvpn-bootstrap/bundle/config/server.conf <<'EOF'
   port 1194
   proto udp
   dev tun
   topology subnet
   server 10.8.0.0 255.255.255.0
   client-config-dir /var/lib/openvpn/ccd
   ca /var/lib/openvpn/pki/ca.crt
   cert /var/lib/openvpn/pki/issued/server.crt
   key /var/lib/openvpn/pki/private/server.key
   dh /var/lib/openvpn/pki/dh.pem
   tls-auth /var/lib/openvpn/pki/ta.key 0
   persist-key
   persist-tun
   keepalive 10 120
   user nobody
   group nobody
   cipher AES-256-GCM
   auth SHA256
   verb 3
   EOF
   ```
6. Copy the generated PKI files into the bundle:
   ```bash
   cp ~/openvpn-bootstrap/easy-rsa/pki/ca.crt ~/openvpn-bootstrap/bundle/pki/
   cp ~/openvpn-bootstrap/easy-rsa/pki/dh.pem ~/openvpn-bootstrap/bundle/pki/
   cp ~/openvpn-bootstrap/easy-rsa/pki/ta.key ~/openvpn-bootstrap/bundle/pki/
   cp ~/openvpn-bootstrap/easy-rsa/pki/issued/server.crt ~/openvpn-bootstrap/bundle/pki/issued/
   cp ~/openvpn-bootstrap/easy-rsa/pki/private/server.key ~/openvpn-bootstrap/bundle/pki/private/
   cp ~/openvpn-bootstrap/easy-rsa/pki/issued/client1.crt ~/openvpn-bootstrap/bundle/pki/issued/
   cp ~/openvpn-bootstrap/easy-rsa/pki/private/client1.key ~/openvpn-bootstrap/bundle/pki/private/
   ```
7. Build a client profile for the first client:
   ```bash
   cat > ~/openvpn-bootstrap/bundle/clients/client1.ovpn <<EOF
   client
   dev tun
   proto udp
   remote vpn.gynx.cc 1194
   nobind
   persist-key
   persist-tun
   remote-cert-tls server
   cipher AES-256-GCM
   auth SHA256
   key-direction 1
   verb 3

   <ca>
   $(cat ~/openvpn-bootstrap/easy-rsa/pki/ca.crt)
   </ca>
   <cert>
   $(cat ~/openvpn-bootstrap/easy-rsa/pki/issued/client1.crt)
   </cert>
   <key>
   $(cat ~/openvpn-bootstrap/easy-rsa/pki/private/client1.key)
   </key>
   <tls-auth>
   $(cat ~/openvpn-bootstrap/easy-rsa/pki/ta.key)
   </tls-auth>
   EOF
   ```
8. Upload the bundle to S3 after Terraform creates the bucket:
   ```bash
   aws s3 sync ~/openvpn-bootstrap/bundle/ "s3://<openvpn_config_bucket_name>/<openvpn_config_s3_prefix>/"
   ```
9. Launch the stack or recycle the instance so it pulls the uploaded bundle on boot.

Cloudflare boot-time DNS update:

- The instance reads the token from `/infra/vpn/cloudflare/api-token` and the zone ID from `/infra/vpn/cloudflare/zone-id` by default.
- Both SSM paths are configurable through Terraform variables if you want a different hierarchy.
- `update-vpn-dns.service` runs on every boot, discovers the current public IP, and creates or updates the `A` record for `vpn.gynx.cc`.
