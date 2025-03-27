variable "project_name" { type = string }
variable "environment" { type = string }
variable "instance_type" { type = string }
variable "key_name" {
  type    = string
  default = ""
}
variable "ami_id" { type = string }
variable "vpc_id" { type = string }
variable "public_subnet_ids" { type = list(string) }
variable "private_subnet_ids" { type = list(string) }
variable "ec2_iam_profile_name" { type = string }
variable "desired_capacity" { type = number }
variable "min_size" { type = number }
variable "max_size" { type = number }
variable "allowed_ssh_cidr" { type = list(string) }
variable "common_tags" { type = map(string) }
variable "log_bucket_name" { type = string }
variable "log_bucket_prefix_path" {
  type    = string
  default = ""
}
variable "aws_region" { type = string }
variable "aws_account_id" { type = string }
