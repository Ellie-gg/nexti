terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "~> 2.3"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    random = {
      source = "hashicorp/random"
      version = "~> 3.5"
    }
  }
  required_version = ">= 1.3.0"
}

data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}
data "aws_caller_identity" "current" {}

locals {
  azs            = slice(data.aws_availability_zones.available.names, 0, 2)
  project_prefix = "${var.project_name}-${var.environment}"
  account_id     = data.aws_caller_identity.current.account_id
  lambda_destination_log_group_name = "/${local.project_prefix}/s3-log-summary"
}

module "vpc" {
  source = "./modules/vpc"

  project_name         = var.project_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr_block
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = local.azs
  common_tags          = var.common_tags
}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}
resource "aws_iam_role" "ec2_role" {
  name               = "${local.project_prefix}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  description        = "Role EC2 (SSM, CWLogs, XRay)"
  tags               = var.common_tags
}
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${local.project_prefix}-ec2-profile"
  role = aws_iam_role.ec2_role.name
  tags = var.common_tags
}
resource "aws_iam_role_policy_attachment" "ec2_ssm_core" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_role_policy_attachment" "ec2_cloudwatch_agent" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}
resource "aws_iam_role_policy_attachment" "ec2_xray_write" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "random_string" "log_bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}
resource "aws_s3_bucket" "logs" {
  bucket_prefix = "${var.log_bucket_prefix}-"
  tags          = merge(var.common_tags, { Name = "${local.project_prefix}-logs-bucket" })
  force_destroy = true
}
resource "aws_s3_bucket_versioning" "logs_versioning" {
  bucket = aws_s3_bucket.logs.id
  versioning_configuration {
    status = "Enabled"
  }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "logs_sse_kms" {
  bucket = aws_s3_bucket.logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}
resource "aws_s3_bucket_public_access_block" "logs_pab" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}
resource "aws_s3_bucket_ownership_controls" "logs_ownership" {
  bucket = aws_s3_bucket.logs.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}
resource "aws_s3_bucket_acl" "logs_acl" {
  depends_on = [aws_s3_bucket_ownership_controls.logs_ownership]
  bucket     = aws_s3_bucket.logs.id
  acl        = "private"
}
data "aws_elb_service_account" "main" {}
data "aws_iam_policy_document" "s3_logs_policy_doc" {
  statement {
    sid    = "AllowALBWrite"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["elasticloadbalancing.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.logs.arn}/alb-logs/AWSLogs/${local.account_id}/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}
resource "aws_s3_bucket_policy" "s3_logs_policy" {
  bucket     = aws_s3_bucket.logs.id
  policy     = data.aws_iam_policy_document.s3_logs_policy_doc.json
  depends_on = [aws_s3_bucket_public_access_block.logs_pab]
}

module "asg" {
  source                 = "./modules/asg"
  project_name           = var.project_name
  environment            = var.environment
  instance_type          = var.asg_instance_type
  key_name               = var.key_name
  ami_id                 = var.ami_id
  vpc_id                 = module.vpc.vpc_id
  public_subnet_ids      = module.vpc.public_subnet_ids
  private_subnet_ids     = module.vpc.private_subnet_ids
  ec2_iam_profile_name   = aws_iam_instance_profile.ec2_profile.name
  desired_capacity       = var.asg_desired_capacity
  min_size               = var.asg_min_size
  max_size               = var.asg_max_size
  allowed_ssh_cidr       = var.allowed_ssh_cidr
  common_tags            = var.common_tags
  log_bucket_name        = aws_s3_bucket.logs.bucket
  log_bucket_prefix_path = "alb-logs"
  aws_region             = var.aws_region
  aws_account_id         = local.account_id
  depends_on             = [ module.vpc, aws_iam_instance_profile.ec2_profile, aws_s3_bucket_policy.s3_logs_policy ]
}
module "rds" {
  source                 = "./modules/rds"
  project_name           = var.project_name
  environment            = var.environment
  db_instance_class      = var.db_instance_class
  db_allocated_storage   = var.db_allocated_storage
  db_engine              = var.db_engine
  db_engine_version      = var.db_engine_version
  db_name                = var.db_name
  db_username            = var.db_username
  db_password            = var.db_password
  vpc_id                 = module.vpc.vpc_id
  subnet_ids             = module.vpc.private_subnet_ids
  ec2_security_group_id = module.asg.ec2_sg_id
  common_tags            = var.common_tags
  depends_on             = [module.asg]
}
module "route53" {
  source       = "./modules/route53"
  providers    = { aws = aws.us-east-1 }
  domain_name  = var.domain_name
  project_name = var.project_name
  environment  = var.environment
  common_tags  = var.common_tags
  record_name  = "${var.environment}-${var.app_hostname}"
  alb_dns_name = module.asg.alb_dns_name
  alb_zone_id  = module.asg.alb_zone_id
  depends_on   = [module.asg]
}
resource "aws_sns_topic" "alarms_topic" {
  name = "${local.project_prefix}-alarms-topic"
  tags = merge(var.common_tags, { Name = "${local.project_prefix}-alarms-topic" })
}
resource "aws_sns_topic_subscription" "alarms_email_target" {
  topic_arn = aws_sns_topic.alarms_topic.arn
  protocol  = "email"
  endpoint  = var.admin_email
}
resource "aws_sns_topic" "s3_logs_topic" {
  name = "${local.project_prefix}-s3-logs-alerts"
  tags = merge(var.common_tags, { Name = "${local.project_prefix}-s3-logs-alerts" })
}
resource "aws_sns_topic_subscription" "s3_logs_email_target" {
  topic_arn = aws_sns_topic.s3_logs_topic.arn
  protocol  = "email"
  endpoint  = var.admin_email
}
resource "aws_sqs_queue" "s3_logs_queue" {
  name = "${local.project_prefix}-s3-logs-queue"
  tags = merge(var.common_tags, { Name = "${local.project_prefix}-s3-logs-queue" })
}
data "archive_file" "lambda_log_parser_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_code"
  output_path = "${path.module}/${var.lambda_log_parser_zip_path}"
}
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}
resource "aws_iam_role" "lambda_log_parser_role" {
  name               = "${local.project_prefix}-lambda-log-parser-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = var.common_tags
}
data "aws_iam_policy_document" "lambda_log_parser_policy_doc" {
  statement {
    sid       = "CWLogs"
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/aws/lambda/${local.project_prefix}-lambda-log-parser:*", "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:${local.lambda_destination_log_group_name}:*"]
  }
  statement {
    sid     = "SNSPublishError" # Allow lambda to publish error notifications
    effect  = "Allow"
    actions = ["sns:Publish"]
    resources = [aws_sns_topic.alarms_topic.arn] # Publish errors to the main alarm topic
  }
  # Add S3 GetObject permission if the lambda needs to read the log file content
  statement {
    sid       = "S3GetObject"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.logs.arn}/*"]
  }
}
resource "aws_iam_policy" "lambda_log_parser_policy" {
  name   = "${local.project_prefix}-lambda-log-parser-policy"
  policy = data.aws_iam_policy_document.lambda_log_parser_policy_doc.json
  tags   = var.common_tags
}
resource "aws_iam_role_policy_attachment" "lambda_log_parser_attach" {
  role       = aws_iam_role.lambda_log_parser_role.name
  policy_arn = aws_iam_policy.lambda_log_parser_policy.arn
}
resource "aws_iam_role_policy_attachment" "lambda_basic_execution_attach" {
  role       = aws_iam_role.lambda_log_parser_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${local.project_prefix}-lambda-log-parser"
  retention_in_days = 7
  tags              = var.common_tags
}
resource "aws_cloudwatch_log_group" "lambda_destination_lg" {
  name              = local.lambda_destination_log_group_name
  retention_in_days = 30
  tags              = merge(var.common_tags, { Name = local.lambda_destination_log_group_name })
}
resource "aws_lambda_function" "log_parser" {
  function_name    = "${local.project_prefix}-lambda-log-parser"
  filename         = data.archive_file.lambda_log_parser_zip.output_path
  source_code_hash = data.archive_file.lambda_log_parser_zip.output_base64sha256
  role             = aws_iam_role.lambda_log_parser_role.arn
  handler          = var.lambda_log_parser_handler
  runtime          = var.lambda_log_parser_runtime
  timeout          = 60
  memory_size      = 256
  environment {
    variables = {
      SNS_TOPIC_ARN              = aws_sns_topic.alarms_topic.arn # Topic for error notifications
      LOG_LEVEL                  = "INFO"
      DESTINATION_LOG_GROUP_NAME = aws_cloudwatch_log_group.lambda_destination_lg.name
    }
  }
  tags = merge(var.common_tags, { Name = "${local.project_prefix}-lambda-log-parser" })
  depends_on = [
    aws_iam_role_policy_attachment.lambda_log_parser_attach,
    aws_iam_role_policy_attachment.lambda_basic_execution_attach,
    aws_cloudwatch_log_group.lambda_log_group,
    aws_cloudwatch_log_group.lambda_destination_lg
  ]
}
resource "aws_lambda_permission" "allow_sns_invoke_lambda" {
  statement_id  = "AllowSNSInvokeLambda-${local.project_prefix}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.log_parser.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.s3_logs_topic.arn
}
resource "aws_sns_topic_subscription" "s3_logs_sqs_target" {
  topic_arn              = aws_sns_topic.s3_logs_topic.arn
  protocol               = "sqs"
  endpoint               = aws_sqs_queue.s3_logs_queue.arn
  raw_message_delivery   = false
  confirmation_timeout_in_minutes = 1
}
resource "aws_sns_topic_subscription" "s3_logs_lambda_target" {
  topic_arn = aws_sns_topic.s3_logs_topic.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.log_parser.arn
}
resource "aws_s3_bucket_notification" "logs_notification" {
  bucket = aws_s3_bucket.logs.id
  topic {
    topic_arn = aws_sns_topic.s3_logs_topic.arn
    events    = ["s3:ObjectCreated:*"]
  }
  depends_on = [
    aws_sns_topic_subscription.s3_logs_sqs_target,
    aws_sns_topic_subscription.s3_logs_lambda_target,
    aws_lambda_permission.allow_sns_invoke_lambda
  ]
}
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${local.project_prefix}-ASG-High-CPU"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 75
  alarm_description   = "CPU media do ASG ${module.asg.asg_name} acima de 75%"
  actions_enabled     = true
  alarm_actions       = [aws_sns_topic.alarms_topic.arn]
  ok_actions          = [aws_sns_topic.alarms_topic.arn]
  dimensions          = { AutoScalingGroupName = module.asg.asg_name }
  tags                = merge(var.common_tags, { Name = "${local.project_prefix}-high-cpu-alarm" })
}
resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${local.project_prefix}-ALB-Unhealthy-Hosts"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Maximum"
  threshold           = 1
  alarm_description   = "Pelo menos 1 host no TG ${module.asg.alb_target_group_name} esta UnHealthy"
  actions_enabled     = true
  alarm_actions       = [aws_sns_topic.alarms_topic.arn]
  ok_actions          = [aws_sns_topic.alarms_topic.arn]
  treat_missing_data  = "notBreaching"
  dimensions          = { TargetGroup = module.asg.alb_target_group_arn_suffix, LoadBalancer = module.asg.alb_arn_suffix }
  tags                = merge(var.common_tags, { Name = "${local.project_prefix}-unhealthy-hosts-alarm" })
}
resource "aws_cloudwatch_metric_alarm" "log_bucket_object_count" {
  alarm_name          = "${local.project_prefix}-LogBucket-ObjectCount-High"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "NumberOfObjects"
  namespace           = "AWS/S3"
  period              = 86400
  statistic           = "Average"
  threshold           = var.log_alarm_object_count_threshold
  alarm_description   = "Numero de objetos no bucket ${aws_s3_bucket.logs.bucket} excedeu ${var.log_alarm_object_count_threshold}."
  actions_enabled     = true
  alarm_actions       = [aws_sns_topic.alarms_topic.arn]
  ok_actions          = [aws_sns_topic.alarms_topic.arn]
  treat_missing_data  = "notBreaching"
  dimensions = {
    BucketName  = aws_s3_bucket.logs.bucket
    StorageType = "AllStorageTypes"
  }
  tags = merge(var.common_tags, { Name = "${local.project_prefix}-log-bucket-object-count-alarm" })
}
resource "aws_cloudwatch_dashboard" "main_dashboard" {
  dashboard_name = "${local.project_prefix}-MainDashboard"
  dashboard_body = jsonencode({
    widgets = [
      { type = "metric", x = 0, y = 0, width = 12, height = 6, properties = { metrics = [ ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", module.rds.db_instance_identifier, { stat = "Average", period = 300, label = "RDS Connections (Avg)" }], [".", ".", ".", ".", { stat = "Maximum", period = 300, label = "RDS Connections (Max)" }] ], view = "timeSeries", stacked = false, region = var.aws_region, title = "RDS Database Connections (${module.rds.db_instance_identifier})" } },
      { type = "metric", x = 12, y = 0, width = 12, height = 6, properties = { metrics = [ [ "AWS/EC2", "CPUUtilization", "AutoScalingGroupName", module.asg.asg_name, { stat = "Average", period = 300, label = "ASG CPU Utilization (%)" } ] ], view = "timeSeries", stacked = false, region = var.aws_region, title = "ASG CPU Utilization", yAxis = { left = { min = 0, max = 100 } } } },
      { type = "metric", x = 0, y = 6, width = 12, height = 6, properties = { metrics = [ ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", module.asg.alb_arn_suffix, { stat = "Sum", period = 300, label = "ALB Requests" } ], ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", module.asg.alb_arn_suffix, { stat = "Sum", period = 300, label = "ALB 5xx Errors", yAxis = "right" } ] ], view = "timeSeries", stacked = false, region = var.aws_region, title = "ALB Requests & 5xx Errors", yAxis = { left = { min = 0 }, right = { min = 0 } } } },
      { type = "metric", x = 12, y = 6, width = 12, height = 6, properties = { metrics = [ ["AWS/ApplicationELB", "UnHealthyHostCount", "TargetGroup", module.asg.alb_target_group_arn_suffix, "LoadBalancer", module.asg.alb_arn_suffix, { stat = "Maximum", period = 60, label = "Unhealthy Hosts" } ], ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", module.asg.alb_target_group_arn_suffix, "LoadBalancer", module.asg.alb_arn_suffix, { stat = "Minimum", period = 60, label = "Healthy Hosts" } ] ], view = "timeSeries", stacked = false, region = var.aws_region, title = "ALB Target Health", yAxis = { left = { min = 0 } } } },
      { type = "log", x = 0, y = 12, width = 24, height = 6, properties = { query = "SOURCE '${module.asg.ec2_log_group_name}' | fields @timestamp, @message | sort @timestamp desc | limit 20", region = var.aws_region, title = "EC2 System Logs (Last 20)" } }
    ]
  })
}
