output "zone_id" { value = data.aws_route53_zone.selected.zone_id }
output "record_fqdn" { value = aws_route53_record.app.fqdn }
output "name_servers" { value = data.aws_route53_zone.selected.name_servers }
