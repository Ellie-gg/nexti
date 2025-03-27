terraform {
  required_providers { aws = { source = "hashicorp/aws" } }
}
locals {
  record_name_clean = trimsuffix(var.record_name, ".")
  domain_name_clean = trimsuffix(var.domain_name, ".")
}
data "aws_route53_zone" "selected" {
  name = local.domain_name_clean
  private_zone = false
}
resource "aws_route53_record" "app" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name = "${local.record_name_clean}.${data.aws_route53_zone.selected.name}"
  type = "A"
  alias {
    name = var.alb_dns_name
    zone_id = var.alb_zone_id
    evaluate_target_health = true
  }
}
