variable "aws_region" {
  description = "AWS region for Bedrock and Lambda."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix for created resources."
  type        = string
  default     = "conizy-bedrock-chat"
}

variable "model_id" {
  description = "Bedrock model ID. Cheapest recommended: Nova Micro."
  type        = string
  default     = "amazon.nova-micro-v1:0"
}
