output "db_endpoint" {
  description = "Endpoint RDS"
  value       = aws_db_instance.main.endpoint
  sensitive   = true
}
output "db_port" {
  description = "Porta RDS"
  value       = aws_db_instance.main.port
}
output "db_name" {
  description = "Nome do DB"
  value       = aws_db_instance.main.db_name
}
output "db_instance_id" {
  description = "ID da Instancia RDS (Legado)"
  value       = aws_db_instance.main.id
}
output "db_instance_identifier" {
  description = "Identificador da Instancia RDS (usado como dimensão CW)"
  value       = aws_db_instance.main.identifier
}
output "rds_sg_id" {
  description = "ID do Security Group criado para o RDS"
  value       = aws_security_group.rds_sg.id
}
