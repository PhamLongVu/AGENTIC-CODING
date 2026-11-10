variable "name" {
  type        = string
  description = "Resource name prefix"
}

variable "account_id" {
  type        = string
  description = "AWS account id (for inference-profile ARNs). Never hardcoded — passed by the environment."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to all resources"
}
