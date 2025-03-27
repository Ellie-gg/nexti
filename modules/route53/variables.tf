variable "project_name" { type = string }
variable "environment" { type = string }
variable "domain_name" { type = string }
variable "common_tags" { type = map(string) }
variable "record_name" { type = string }
variable "alb_dns_name" { type = string }
variable "alb_zone_id" { type = string }
