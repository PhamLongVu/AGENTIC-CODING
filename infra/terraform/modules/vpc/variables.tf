variable "name" {
  type        = string
  description = "Resource name prefix"
}

variable "cidr_block" {
  type        = string
  default     = "10.42.0.0/24"
  description = "VPC CIDR (single /24 is plenty for a POC)"
}

variable "availability_zone" {
  type        = string
  description = "Single AZ for the whole POC (baseline: no multi-AZ)"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to all resources"
}
