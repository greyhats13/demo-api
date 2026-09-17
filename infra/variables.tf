variable "aws_region" {
  default = "us-east-1"
}

variable "app_name" {
  default = "demo-api"
}

# Database password used by the application.
variable "db_password_parameter_arn" {
  description = "ARN of the SSM SecureString parameter that holds the DB password."
  type        = string
}

variable "image_tag" {
  default = "latest"
}

variable "certificate_arn" {
  description = "ACM certificate ARN for the ALB HTTPS listener."
  type        = string
}
