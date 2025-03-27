output "vpc_id" {
  description = "ID da VPC criada"
  value       = module.vpc.vpc_id
}
output "public_subnet_ids" {
  description = "IDs das subnets publicas"
  value       = module.vpc.public_subnet_ids
}
output "private_subnet_ids" {
  description = "IDs das subnets privadas"
  value       = module.vpc.private_subnet_ids
}
output "alb_dns_name" {
  description = "DNS publico do Application Load Balancer"
  value       = module.asg.alb_dns_name
}
output "rds_endpoint" {
  description = "Endpoint do banco de dados RDS"
  value       = module.rds.db_endpoint
  sensitive   = true
}
output "rds_port" {
  description = "Porta do banco de dados RDS"
  value       = module.rds.db_port
}
output "asg_name" {
  description = "Nome do Auto Scaling Group"
  value       = module.asg.asg_name
}
output "route53_service_fqdn" {
  description = "FQDN do servico no Route 53"
  value       = module.route53.record_fqdn
}
output "service_url" {
  description = "URL final do servico (HTTP)"
  value       = "http://${module.route53.record_fqdn}"
}
output "route53_name_servers" {
  description = "Name Servers da Zona Hospedada"
  value       = module.route53.name_servers
}
output "sns_alarms_topic_arn" {
  description = "ARN do topico SNS para alarmes"
  value       = aws_sns_topic.alarms_topic.arn
}
output "log_bucket_name" {
  description = "Nome do bucket S3 criado para logs"
  value       = aws_s3_bucket.logs.bucket
}
output "log_bucket_arn" {
  description = "ARN do bucket S3 criado para logs"
  value       = aws_s3_bucket.logs.arn
}
output "sns_s3_logs_topic_arn" {
  description = "ARN do topico SNS para notificacoes de log S3"
  value       = aws_sns_topic.s3_logs_topic.arn
}
output "sqs_s3_logs_queue_url" {
  description = "URL da fila SQS para notificacoes de log S3"
  value       = aws_sqs_queue.s3_logs_queue.id
}
output "sqs_s3_logs_queue_arn" {
  description = "ARN da fila SQS para notificacoes de log S3"
  value       = aws_sqs_queue.s3_logs_queue.arn
}
output "lambda_log_parser_function_name" {
  description = "Nome da funcao Lambda para processar logs S3"
  value       = aws_lambda_function.log_parser.function_name
}
output "lambda_log_parser_function_arn" {
  description = "ARN da funcao Lambda para processar logs S3"
  value       = aws_lambda_function.log_parser.arn
}
output "cloudwatch_dashboard_name" {
  description = "Nome do Dashboard CloudWatch criado"
  value       = aws_cloudwatch_dashboard.main_dashboard.dashboard_name
}
output "ec2_log_group_name" {
  description = "Nome do Log Group para logs do sistema EC2"
  value       = module.asg.ec2_log_group_name
}
output "ssh_command_example" {
  description = "Exemplo de comando para conectar via SSM"
  value       = "aws ssm start-session --target <INSTANCE_ID>"
}
