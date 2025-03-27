locals { project_prefix = "${var.project_name}-${var.environment}" }
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = merge(var.common_tags, { Name = "${local.project_prefix}-vpc" })
}
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags   = merge(var.common_tags, { Name = "${local.project_prefix}-igw" })
}
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = element(var.public_subnet_cidrs, count.index)
  availability_zone       = element(var.availability_zones, count.index)
  map_public_ip_on_launch = true
  tags = merge(var.common_tags, { Tier = "Public", Name = "${local.project_prefix}-public-subnet-${count.index + 1}" })
}
resource "aws_subnet" "private" {
  count                   = length(var.private_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = element(var.private_subnet_cidrs, count.index)
  availability_zone       = element(var.availability_zones, count.index)
  map_public_ip_on_launch = false
  tags = merge(var.common_tags, { Tier = "Private", Name = "${local.project_prefix}-private-subnet-${count.index + 1}" })
}
resource "aws_eip" "nat" {
  count  = length(var.public_subnet_cidrs)
  domain = "vpc"
  tags   = merge(var.common_tags, { Name = "${local.project_prefix}-nat-eip-${count.index + 1}" })
  depends_on = [aws_internet_gateway.gw]
}
resource "aws_nat_gateway" "main" {
  count         = length(var.public_subnet_cidrs)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  tags          = merge(var.common_tags, { Name = "${local.project_prefix}-nat-gw-${count.index + 1}" })
  depends_on    = [aws_internet_gateway.gw]
}
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = merge(var.common_tags, { Name = "${local.project_prefix}-public-rt" })
}
resource "aws_route_table" "private" {
  count  = length(var.private_subnet_cidrs)
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }
  tags = merge(var.common_tags, { Name = "${local.project_prefix}-private-rt-${count.index + 1}" })
}
resource "aws_route_table_association" "public" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table_association" "private" {
  count          = length(var.private_subnet_cidrs)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}
