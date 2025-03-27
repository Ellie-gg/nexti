locals {
  project_prefix     = "${var.project_name}-${var.environment}"
  log_group_name_ec2 = "/aws/ec2/${local.project_prefix}/var/log/messages"
}
data "aws_elb_service_account" "main" {}

resource "aws_security_group" "alb_sg" {
  name        = "${local.project_prefix}-alb-sg"
  description = "Permite HTTP(S) da internet para o ALB"
  vpc_id      = var.vpc_id
  ingress {
    description      = "Allow HTTP"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(var.common_tags, { Name = "${local.project_prefix}-alb-sg" })
}
resource "aws_security_group" "ec2_sg" {
  name        = "${local.project_prefix}-ec2-sg"
  description = "SG para instancias EC2 no ASG"
  vpc_id      = var.vpc_id
  ingress {
    description     = "Allow HTTP from ALB SG"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }
  dynamic "ingress" {
    for_each = var.key_name != "" && length(var.allowed_ssh_cidr) > 0 ? [1] : []
    content {
      description = "Allow SSH"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.allowed_ssh_cidr
    }
  }
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(var.common_tags, { Name = "${local.project_prefix}-ec2-sg" })
}
resource "aws_lb" "main" {
  name                       = "${local.project_prefix}-alb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb_sg.id]
  subnets                    = var.public_subnet_ids
  enable_deletion_protection = false
  access_logs {
    bucket  = var.log_bucket_name
    prefix  = var.log_bucket_prefix_path
    enabled = true
  }
  tags = merge(var.common_tags, { Name = "${local.project_prefix}-alb" })
}
resource "aws_lb_target_group" "main" {
  name        = substr("${local.project_prefix}-tg", 0, 32)
  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"
  health_check {
    enabled             = true
    interval            = 30
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }
  tags = merge(var.common_tags, { Name = "${local.project_prefix}-tg" })
  deregistration_delay = 60
}
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}
resource "aws_cloudwatch_log_group" "ec2_logs" {
  name              = local.log_group_name_ec2
  retention_in_days = 14
  tags              = merge(var.common_tags, { Name = "${local.project_prefix}-ec2-system-logs" })
}
data "cloudinit_config" "user_data" {
  gzip          = true
  base64_encode = true
  part {
    content_type = "text/x-shellscript"
    filename     = "bootstrap.sh"
    content      = <<-EOF
      #!/bin/bash
      set -euxo pipefail; exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
      echo "INFO: Iniciando User Data Aprimorado..."; yum update -y; yum install -y httpd amazon-ssm-agent curl amazon-cloudwatch-agent aws-xray-daemon stress
      echo "INFO: Iniciando e habilitando serviços..."; systemctl enable --now ssm-agent; systemctl enable --now httpd
      echo "INFO: Configurando CloudWatch Agent..."; CW_AGENT_CONFIG_FILE="/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json"; CW_LOG_GROUP="${local.log_group_name_ec2}";
      cat << CW_AGENT_CONF > $${CW_AGENT_CONFIG_FILE}; { "agent": { "run_as_user": "root" }, "logs": { "logs_collected": { "files": { "collect_list": [ { "file_path": "/var/log/messages", "log_group_name": "$${CW_LOG_GROUP}", "log_stream_name": "{instance_id}/messages", "timestamp_format": "%b %d %H:%M:%S", "timezone": "Local" } ] } } } }; CW_AGENT_CONF
      echo "INFO: Iniciando e habilitando CloudWatch Agent..."; /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:$${CW_AGENT_CONFIG_FILE} -s; systemctl enable amazon-cloudwatch-agent
      echo "INFO: Iniciando e habilitando X-Ray Daemon..."; systemctl enable --now xray
      echo "INFO: Criando pagina de teste..."; INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id); AZ=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone); REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
      cat <<HTML > /var/www/html/index.html; <html><head><title>EC2 OK</title></head><body><h1>Instancia EC2 Funcionando!</h1><p><b>ID:</b> $${INSTANCE_ID}</p><p><b>AZ:</b> $${AZ}</p><p><b>Region:</b> $${REGION}</p><hr><small>$(date)</small></body></html>; HTML; chown apache:apache /var/www/html/index.html
      echo "INFO: User Data Aprimorado concluido."
      EOF
  }
}
resource "aws_launch_template" "main" {
  name_prefix = "${local.project_prefix}-lt-"
  description = "Launch template aprimorado para ${local.project_prefix}"
  image_id = var.ami_id
  instance_type = var.instance_type
  key_name = var.key_name != "" ? var.key_name : null
  iam_instance_profile {
    name = var.ec2_iam_profile_name
  }
  network_interfaces {
    associate_public_ip_address = false
    delete_on_termination = true
    security_groups = [aws_security_group.ec2_sg.id]
  }
  metadata_options {
    http_endpoint = "enabled"
    http_tokens = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags = "enabled"
  }
  user_data = data.cloudinit_config.user_data.rendered
  monitoring {
    enabled = true
  }
  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.common_tags, { Name = "${local.project_prefix}-instance" })
  }
  tag_specifications {
    resource_type = "volume"
    tags          = merge(var.common_tags, { Name = "${local.project_prefix}-volume" })
  }
  tags = merge(var.common_tags, {
    Name = "${local.project_prefix}-lt"
  })
  lifecycle {
    create_before_destroy = true
  }
}
resource "aws_autoscaling_group" "main" {
  name_prefix = "${local.project_prefix}-asg-"
  desired_capacity = var.desired_capacity
  min_size = var.min_size
  max_size = var.max_size
  vpc_zone_identifier = var.private_subnet_ids
  launch_template {
    id = aws_launch_template.main.id
    version = "$Latest"
  }
  target_group_arns = [aws_lb_target_group.main.arn]
  health_check_type = "ELB"
  health_check_grace_period = 300
  termination_policies = ["OldestLaunchTemplate", "OldestInstance", "Default"]
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 120
    }
  }
  dynamic "tag" {
    for_each = merge(var.common_tags, { Name = "${local.project_prefix}-instance" })
    content {
      key = tag.key
      value = tag.value
      propagate_at_launch = true
    }
  }
  lifecycle { create_before_destroy = true }
  depends_on = [aws_cloudwatch_log_group.ec2_logs]
}
resource "aws_autoscaling_policy" "cpu_target_tracking" {
  name                   = "${local.project_prefix}-cpu-target"
  autoscaling_group_name = aws_autoscaling_group.main.name
  policy_type            = "TargetTrackingScaling"
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value     = 60.0
    disable_scale_in = false
  }
}
