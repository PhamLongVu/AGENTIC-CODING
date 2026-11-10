# =============================================================================
# VPC module — minimal single-AZ POC network (ADR-0001)
# =============================================================================
# Deliberately NOT the plan's original 3-AZ public/private/data topology:
# the confirmed baseline scopes the MVP to one instance in one AZ. Growth
# triggers for a full topology are documented in ADR-0001.
# =============================================================================
resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, {
    Name = "${var.name}-vpc"
  })
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.cidr_block, 4, 0)
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true # single-instance POC; instance has no EIP needs beyond this

  tags = merge(var.tags, {
    Name = "${var.name}-public"
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-igw"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(var.tags, {
    Name = "${var.name}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}
