variable "name" {
  type        = string
  description = "Resource name prefix"
}

variable "vpc_id" {
  type        = string
  description = "VPC id"
}

variable "subnet_id" {
  type        = string
  description = "Subnet id (single-AZ POC)"
}

variable "instance_profile_name" {
  type        = string
  description = "IAM instance profile (Bedrock invoke only — modules/iam)"
}

variable "instance_type" {
  type        = string
  default     = "m6a.2xlarge"
  description = "Sized in ADR-0007 (8 vCPU / 32 GiB for 5 Small workspaces + platform)"
}

variable "root_volume_size_gb" {
  type        = number
  default     = 200
  description = "Holds OS + images + all workspace volumes"
}

variable "admin_cidr" {
  type        = string
  description = "CIDR allowed SSH (and ideally 7080 for the operator)"
}

variable "dev_cidr" {
  type        = string
  default     = "0.0.0.0/0"
  description = "CIDR allowed to reach the Coder UI. POC default open; restrict when the team CIDR is known."
}

variable "ssh_key_name" {
  type        = string
  default     = null
  description = "Optional EC2 key pair (null = SSM Session Manager only)"
}

variable "associate_eip" {
  type        = bool
  default     = true
  description = "Stable public IP for CODER_ACCESS_URL across stop/start (cost: idle EIP on stopped instance)"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to all resources"
}
