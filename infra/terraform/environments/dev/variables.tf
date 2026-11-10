variable "aws_region" {
  type        = string
  default     = "ap-southeast-1"
  description = "Confirmed baseline region (Singapore)"
}

variable "environment_name" {
  type        = string
  default     = "cloud-coding-poc"
  description = "Prefix for every resource"
}

variable "availability_zone" {
  type        = string
  default     = "ap-southeast-1a"
  description = "Single-AZ by design (ADR-0001)"
}

variable "vpc_cidr" {
  type        = string
  default     = "10.42.0.0/24"
}

variable "instance_type" {
  type        = string
  default     = "m6a.2xlarge"
  description = "ADR-0007 sizing; changing requires cost review"
}

variable "root_volume_size_gb" {
  type        = number
  default     = 200
}

variable "admin_cidr" {
  type        = string
  description = "MUST be set via tfvars — operator's source CIDR for SSH"
}

variable "dev_cidr" {
  type        = string
  default     = "0.0.0.0/0"
  description = "Developers' CIDR for the Coder UI (POC: open; tighten when known)"
}

variable "ssh_key_name" {
  type        = string
  default     = null
}

variable "cost_center" {
  type        = string
  default     = "mvp-poc"
}
