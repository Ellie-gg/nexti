variable "aws_region" {
  description = "Regiao AWS"
  type        = string
  default     = "us-east-1"
}
variable "common_tags" {
  description = "Tags comuns"
  type        = map(string)
  default = {
    Project     = "nextisimple"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}
variable "project_name" {
  description = "Nome base"
  type        = string
  default     = "nextisimple"
}
variable "environment" {
  description = "Ambiente"
  type        = string
  default     = "dev"
}
variable "vpc_cidr_block" {
  description = "CIDR VPC"
  type        = string
  default     = "10.100.0.0/16"
}
variable "public_subnet_cidrs" {
  description = "CIDRs Subnets Publicas"
  type        = list(string)
  default     = ["10.100.1.0/24", "10.100.2.0/24"]
}
variable "private_subnet_cidrs" {
  description = "CIDRs Subnets Privadas"
  type        = list(string)
  default     = ["10.100.101.0/24", "10.100.102.0/24"]
}
variable "availability_zones" {
  description = "AZs"
  type        = list(string)
  default     = []
}
variable "domain_name" {
  description = "Dominio Route 53 (Zona DEVE existir)"
  type        = string
  default     = "elielnexti.click"
}
variable "app_hostname" {
  description = "Prefixo Hostname App"
  type        = string
  default     = "app"
}
variable "db_instance_class" {
  description = "Classe RDS"
  type        = string
  default     = "db.t3.micro"
}
variable "db_allocated_storage" {
  description = "Storage RDS GB"
  type        = number
  default     = 20
}
variable "db_name" {
  description = "Nome DB"
  type        = string
  default     = "nextisimpledb"
}
variable "db_username" {
  description = "Usuario Master RDS"
  type        = string
  default     = "nextisimpleadmin"
}
variable "db_password" {
  description = "Senha Master RDS (USE TFVARS/ENV!)"
  type        = string
  sensitive   = true
  default     = "MudarSenhaMuitoForte123!"
}
variable "db_engine" {
  description = "Engine DB"
  type        = string
  default     = "postgres"
}
variable "db_engine_version" {
  description = "Versao Engine DB"
  type        = string
  default     = "14"
}
variable "ami_id" {
  description = "AMI EC2"
  type        = string
  default     = "ami-0ac4dfaf1c5c0cce9"
}
variable "asg_instance_type" {
  description = "Tipo Instancia ASG"
  type        = string
  default     = "t2.micro"
}
variable "asg_desired_capacity" {
  description = "Capacidade Desejada ASG"
  type        = number
  default     = 2
}
variable "asg_min_size" {
  description = "Min Size ASG"
  type        = number
  default     = 1
}
variable "asg_max_size" {
  description = "Max Size ASG"
  type        = number
  default     = 2
}
variable "key_name" {
  description = "Nome Chave SSH"
  type        = string
  default     = ""
}
variable "allowed_ssh_cidr" {
  description = "CIDR para SSH direto"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
variable "admin_email" {
  description = "Email Alertas SNS"
  type        = string
  default     = "eliel.garcia@gmail.com"
}
variable "log_bucket_prefix" {
  description = "Prefixo Bucket Logs S3"
  type        = string
  default     = "nextisimple-dev-logs"
}
variable "lambda_log_parser_zip_path" {
  description = "Path Zip Lambda"
  type        = string
  default     = "log_parser.zip"
}
variable "lambda_log_parser_handler" {
  description = "Handler Lambda"
  type        = string
  default     = "log_parser.lambda_handler"
}
variable "lambda_log_parser_runtime" {
  description = "Runtime Lambda"
  type        = string
  default     = "python3.9"
}
variable "log_alarm_object_count_threshold" {
  description = "Threshold Alarme Objetos S3"
  type        = number
  default     = 10000
}
