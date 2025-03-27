locals {
  project_prefix = "${var.project_name}-${var.environment}"
  db_port        = 5432
}
resource "aws_db_subnet_group" "main" {
  name       = "${local.project_prefix}-rds-sng"
  subnet_ids = var.subnet_ids
  tags = merge(var.common_tags, { Name = "${local.project_prefix}-rds-sng" })
}
resource "aws_security_group" "rds_sg" {
  name        = "${local.project_prefix}-rds-sg"
  description = "Controles RDS DB access"
  vpc_id      = var.vpc_id
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(var.common_tags, { Name = "${local.project_prefix}-rds-sg" })
}
resource "aws_security_group_rule" "allow_ec2_ingress" {
  type                     = "ingress"
  description              = "Permite acesso ao DB vindo do SG das EC2"
  from_port                = local.db_port
  to_port                  = local.db_port
  protocol                 = "tcp"
  source_security_group_id = var.ec2_security_group_id
  security_group_id        = aws_security_group.rds_sg.id
}
resource "aws_db_instance" "main" {
  identifier             = "${local.project_prefix}-rds"
  instance_class         = var.db_instance_class
  allocated_storage      = var.db_allocated_storage
  engine                 = var.db_engine
  engine_version         = var.db_engine_version
  db_name                = var.db_name
  username               = var.db_username
  password               = var.db_password
  port                   = local.db_port
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  storage_type           = "gp3"
  publicly_accessible    = false
  skip_final_snapshot    = true
  apply_immediately      = true
  tags = merge(var.common_tags, { Name = "${local.project_prefix}-rds-instance" })
}
