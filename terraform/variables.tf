variable "basename" {
  type        = string
  description = "The base name for all resources"
  default     = "s2tumworkshop0"
}

variable "resource_group_name" {
  type        = string
  description = "rg name. Use only lowercase letters and numbers"
  default     = "TUM-Workshop"
}

variable "location" {
  type        = string
  description = "Azure region where to create resources."
  default     = "West Europe"
}
