# =============================================================================
# POC environment — single EC2 instance, ap-southeast-1 (baseline)
# =============================================================================
# NEVER applied automatically. terraform apply requires explicit owner
# approval in the conversation (CLAUDE.md non-negotiable #2; the approval
# gate is BACKLOG item 3.5). Cost + security implications: docs/operations/
# deployment.md §2–§4.
# =============================================================================

data "aws_caller_identity" "current" {}

locals {
  name = "${var.environment_name}-${var.aws_region}"
  tags = {
    Project     = "cloud-coding-platform"
    Environment = var.environment_name
    ManagedBy   = "terraform"
    CostCenter  = var.cost_center
  }
}

module "vpc" {
  source = "../../modules/vpc"

  name              = local.name
  cidr_block        = var.vpc_cidr
  availability_zone = var.availability_zone
  tags              = local.tags
}

module "iam" {
  source = "../../modules/iam"

  name       = local.name
  account_id = data.aws_caller_identity.current.account_id
  tags       = local.tags
}

module "ec2" {
  source = "../../modules/ec2"

  name                  = local.name
  vpc_id                = module.vpc.vpc_id
  subnet_id             = module.vpc.public_subnet_id
  instance_profile_name = module.iam.instance_profile_name
  instance_type         = var.instance_type
  root_volume_size_gb   = var.root_volume_size_gb
  admin_cidr            = var.admin_cidr
  dev_cidr              = var.dev_cidr
  ssh_key_name          = var.ssh_key_name
  associate_eip         = true
  tags                  = local.tags
}

output "instance_id" {
  value = module.ec2.instance_id
}

output "public_ip" {
  description = "Use as CODER_ACCESS_URL host: http://<ip>:7080"
  value       = module.ec2.public_ip
}

output "ssh_command" {
  value = module.ec2.ssh_command
}

output "post_apply_steps" {
  description = "What the operator does AFTER approval + apply"
  value       = <<-EOT
    1. scripts/aws-noop-until-approved — see docs/operations/deployment.md
    2. rsync repo to the host (or git clone)
    3. on host: deploy/scripts/bootstrap-host.sh
    4. validate:   deploy/scripts/validate-deployment.sh
    5. stop cost:  deploy/scripts/instance-stop.sh
  EOT
}
