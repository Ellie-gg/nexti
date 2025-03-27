output "alb_dns_name" { value = aws_lb.main.dns_name }
output "alb_zone_id" { value = aws_lb.main.zone_id }
output "alb_arn_suffix" { value = aws_lb.main.arn_suffix }
output "alb_target_group_arn_suffix" { value = aws_lb_target_group.main.arn_suffix }
output "alb_target_group_name" { value = aws_lb_target_group.main.name }
output "asg_name" { value = aws_autoscaling_group.main.name }
output "ec2_sg_id" { value = aws_security_group.ec2_sg.id }
output "ec2_log_group_name" { value = aws_cloudwatch_log_group.ec2_logs.name }
