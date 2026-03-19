locals {
  common_tags = merge(
    {
      ManagedBy = "terraform"
    },
    var.tags
  )
}

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["137112412989"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-arm64"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

module "vpc" {
  source  = "aws-ia/vpc/aws"
  version = "~> 4.5"

  name       = var.name
  cidr_block = var.vpc_cidr
  az_count   = var.az_count

  subnets = {
    public = {
      netmask = 24
    }
  }

  tags = local.common_tags
}

resource "aws_ssm_parameter" "cloudflare_api_token" {
  name        = var.cloudflare_api_token_ssm_path
  description = "Cloudflare API token used by the VPN instance at boot."
  type        = "SecureString"
  value       = var.cloudflare_api_token
  tags        = local.common_tags
}

resource "aws_ssm_parameter" "cloudflare_zone_id" {
  name        = var.cloudflare_zone_id_ssm_path
  description = "Cloudflare zone ID used by the VPN instance at boot."
  type        = "String"
  value       = var.cloudflare_zone_id
  tags        = local.common_tags
}

resource "aws_iam_role" "instance" {
  name = "${var.name}-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "parameter_access" {
  name = "${var.name}-parameter-access"
  role = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters"
        ]
        Resource = [
          aws_ssm_parameter.cloudflare_api_token.arn,
          aws_ssm_parameter.cloudflare_zone_id.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "ssm.${var.aws_region}.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_instance_profile" "instance" {
  name = "${var.name}-instance-profile"
  role = aws_iam_role.instance.name

  tags = local.common_tags
}

resource "aws_security_group" "vpn" {
  name        = "${var.name}-vpn"
  description = "Security group for the OpenVPN instance."
  vpc_id      = module.vpc.vpc_attributes.id

  ingress {
    description = "OpenVPN UDP"
    from_port   = var.openvpn_udp_port
    to_port     = var.openvpn_udp_port
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  dynamic "ingress" {
    for_each = toset(var.ssh_ingress_cidrs)

    content {
      description = "Optional SSH"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}

data "cloudinit_config" "userdata" {
  gzip          = false
  base64_encode = true

  part {
    content_type = "text/x-shellscript"
    content = templatefile("${path.module}/userdata.sh.tftpl", {
      aws_region                    = var.aws_region
      openvpn_udp_port              = var.openvpn_udp_port
      cloudflare_api_token_ssm_path = var.cloudflare_api_token_ssm_path
      cloudflare_zone_id_ssm_path   = var.cloudflare_zone_id_ssm_path
      vpn_record_name               = var.vpn_record_name
      cloudflare_record_ttl         = var.cloudflare_record_ttl
      openvpn_state_device_name     = var.openvpn_state_device_name
    })
  }
}

resource "aws_launch_template" "vpn" {
  name_prefix            = "${var.name}-"
  image_id               = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.instance_type
  update_default_version = true

  iam_instance_profile {
    arn = aws_iam_instance_profile.instance.arn
  }

  monitoring {
    enabled = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.vpn.id]
  }

  user_data = data.cloudinit_config.userdata.rendered

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 16
      volume_type           = "gp3"
      delete_on_termination = true
      encrypted             = true
    }
  }

  block_device_mappings {
    device_name = var.openvpn_state_device_name

    ebs {
      volume_size           = var.openvpn_state_volume_size
      volume_type           = "gp3"
      delete_on_termination = true
      encrypted             = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(
      local.common_tags,
      {
        Name = "${var.name}-instance"
      }
    )
  }

  tag_specifications {
    resource_type = "volume"
    tags          = local.common_tags
  }

  tags = local.common_tags
}

resource "aws_autoscaling_group" "vpn" {
  name                      = "${var.name}-asg"
  min_size                  = 1
  max_size                  = 1
  desired_capacity          = 1
  health_check_type         = "EC2"
  health_check_grace_period = 300
  vpc_zone_identifier = [
    for _, subnet in module.vpc.public_subnet_attributes_by_az : subnet.id
  ]

  launch_template {
    id      = aws_launch_template.vpn.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.name}-instance"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = local.common_tags

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}
