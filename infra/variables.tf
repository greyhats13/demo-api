variable "aws_region" {
  default = "us-east-1"
}

variable "app_name" {
  default = "demo-api"
}

# Database password used by the application.
variable "db_password" {
  default = "SuperSecret123!"
}

variable "image_tag" {
  default = "latest"
}
