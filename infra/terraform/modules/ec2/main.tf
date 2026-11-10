# =============================================================================
# EC2 module — the single POC instance (ADR-0001, ADR-0007)
# =============================================================================
# Hard security requirements baked in (docs/architecture/security-model.md):
#   * IMDSv2 REQUIRED (token-based), hop limit = 1  -> containers on docker
#     bridge networks CANNOT reach instance metadata; only the LiteLLM
#     gateway (host network in AWS mode) can.
#   * No SSH key baked in by default (SSM Session Manager optional var);
#     if ssh_enabled, port 22 restricted to admin_cidr.
#   * Security group: 22 (admin cidr), 7080 (coder UI, dev cidr). LiteLLM's
#     4000 is NOT opened — workspaces reach it via the host gateway and the
#     world is blocked.
# =============================================================================

data "aws_ami" "ubuntu_2404" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_security_group" "instance" {
  name   = "${var.name}-sg"
  vpc_id = var.vpc_id

  ingress {
    description = "SSH from admin network only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  ingress {
    description = "Coder UI/API for developers"
    from_port   = 7080
    to_port     = 7080
    protocol    = "tcp"
    cidr_blocks = [var.dev_cidr]
  }

  egress {
    description = "all outbound (registry pulls, Bedrock, DNS)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.name}-sg"
  })
}

resource "aws_instance" "this" {
  ami                    = data.aws_ami.ubuntu_2404.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.instance.id]
  monitoring             = true

  iam_instance_profile = var.instance_profile_name

  metadata_options {
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 1          # blocks containerized access
    instance_metadata_tags      = "enabled"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_size_gb
    encrypted   = true

    tags = merge(var.tags, {
      Name = "${var.name}-root"
    })
  }

  key_name = var.ssh_key_name # null => SSM-only access

  user_data = <<-EOF
    #!/bin/bash
    # Minimal first boot: hostname + docker install. Application bootstrap
    # (env, compose up) is done by deploy/scripts/bootstrap-host.sh after
    # the owner approves and runs it.
    hostnamectl set-hostname ${var.name}
    apt-get update
    apt-get install -y ca-certificates curl gnupg
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable --now docker
  EOF

  user_data_replace_on_change = false

  tags = merge(var.tags, {
    Name = var.name
  })
}

resource "aws_eip" "this" {
  count = var.associate_eip ? 1 : 0

  instance = aws_instance.this.id
  domain   = "vpc"

  tags = merge(var.tags, {
    Name = "${var.name}-eip"
  })
}
