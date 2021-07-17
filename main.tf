
locals {
  security_groups = {
    public = {
      name        = "public_sg"
      description = "public access"
      ingress = {
        open = {
          from        = 0
          to          = 0
          protocol    = -1
          cidr_blocks = ["0.0.0.0/0"]
        }
        tg = {
          from        = 8000
          to          = 8000
          protocol    = "tcp"
          cidr_blocks = ["0.0.0.0/0"]
        }
        http = {
          from        = 80
          to          = 80
          protocol    = "tcp"
          cidr_blocks = ["0.0.0.0/0"]
        }
      }
    }
    rds = {
      name        = "rds_sg"
      description = "rds access"
      ingress = {
        mysql = {
          from        = 3306
          to          = 3306
          protocol    = "tcp"
          cidr_blocks = var.public_cidrs
        }
      }
    }
  }
}


data "aws_availability_zones" "available" {}

resource "random_integer" "random" {
  min = 1
  max = 99
}

resource "random_shuffle" "public_az" {
  input        = data.aws_availability_zones.available.names
  result_count = var.max_subnets
}

resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "vpc-${random_integer.random.id}"
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_subnet" "public_subnet" {
  count                   = var.public_sn_count
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = var.public_cidrs[count.index]
  map_public_ip_on_launch = true
  availability_zone       = random_shuffle.public_az.result[count.index]

  tags = {
    Name = "public_${count.index + 1}"
  }
}

resource "aws_subnet" "private_subnet" {
  count                   = var.private_sn_count
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = var.private_cidrs[count.index]
  map_public_ip_on_launch = false
  availability_zone       = random_shuffle.public_az.result[count.index]

  tags = {
    Name = "private_${count.index + 1}"
  }
}

resource "aws_db_subnet_group" "rds_subnetgroup" {
  count      = var.db_subnet_group ? 1 : 0
  name       = "rds_subnetgroup"
  subnet_ids = aws_subnet.private_subnet.*.id
  tags = {
    Name = "rds_sng"
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "igw"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "public"
  }
}


resource "aws_route" "default_route" {
  route_table_id         = aws_route_table.public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway.id
}


resource "aws_default_route_table" "private_rt" {
  default_route_table_id = aws_vpc.vpc.default_route_table_id

  tags = {
    Name = "private"
  }
}

resource "aws_route_table_association" "public_assoc" {
  count          = var.public_sn_count
  subnet_id      = aws_subnet.public_subnet.*.id[count.index]
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_security_group" "sg" {
  for_each    = local.security_groups
  name        = each.value.name
  description = each.value.description
  vpc_id      = aws_vpc.vpc.id
  lifecycle {
    create_before_destroy = true
  }


  #public Security Group
  dynamic "ingress" {
    for_each = each.value.ingress
    content {
      from_port   = ingress.value.from
      to_port     = ingress.value.to
      protocol    = ingress.value.protocol
      cidr_blocks = ingress.value.cidr_blocks
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
