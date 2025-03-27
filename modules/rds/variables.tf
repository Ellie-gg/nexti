variable "project_name" { type = string }
variable "environment" { type = string }
variable "vpc_id" { type = string }
variable "db_instance_class" { type = string }
variable "db_allocated_storage" { type = number }
variable "db_engine" { type = string }
variable "db_engine_version" { type = string }
variable "db_name" { type = string }
variable "db_username" { type = string }
variable "db_password" {
  type      = string
  sensitive = true
}
variable "subnet_ids" { type = list(string) }
variable "ec2_security_group_id" { type = string }
variable "common_tags" { type = map(string) }
