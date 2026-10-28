provider "aws" {
  region = "ap-southeast-1"
}
data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc_ipam" "lks-vpc-ipam" {
  operating_regions {
    region_name = data.aws_region.current.name
  }
}

resource "aws_vpc" "lks-vpc-serverless" {
  cidr_block                       = "20.1.0.0/20"
  assign_generated_ipv6_cidr_block = true

  instance_tenancy = "default"

  tags = {
    Name = "lks-vpc-serverless"
  }
}

resource "aws_subnet" "lks-vpc-serverless-subnet-public-1" {
  vpc_id = aws_vpc.lks-vpc-serverless.id
  cidr_block = "20.1.0.0/25"
  ipv6_cidr_block = cidrsubnet(aws_vpc.lks-vpc-serverless.ipv6_cidr_block, 8, 1)
  availability_zone = data.aws_availability_zones.available.names[0]
  assign_ipv6_address_on_creation = true
}

resource "aws_subnet" "lks-vpc-serverless-subnet-public-2" {
  vpc_id = aws_vpc.lks-vpc-serverless.id
  cidr_block = "20.1.1.0/25"
  ipv6_cidr_block = cidrsubnet(aws_vpc.lks-vpc-serverless.ipv6_cidr_block, 8, 2)
  availability_zone = data.aws_availability_zones.available.names[1]
  assign_ipv6_address_on_creation = true
}
resource "aws_subnet" "lks-vpc-serverless-subnet-private-1" {
  vpc_id = aws_vpc.lks-vpc-serverless.id
  cidr_block = "20.1.11.0/25"
  ipv6_cidr_block = cidrsubnet(aws_vpc.lks-vpc-serverless.ipv6_cidr_block, 8, 3)
  availability_zone = data.aws_availability_zones.available.names[0]
  assign_ipv6_address_on_creation = true
}

resource "aws_subnet" "lks-vpc-serverless-subnet-private-2" {
  vpc_id = aws_vpc.lks-vpc-serverless.id
  cidr_block = "20.1.12.0/25"
  ipv6_cidr_block = cidrsubnet(aws_vpc.lks-vpc-serverless.ipv6_cidr_block, 8, 4)
  availability_zone = data.aws_availability_zones.available.names[1]
  assign_ipv6_address_on_creation = true
}

resource "aws_security_group" "lks-vpc-sg" {
  name = "lks_vpc_sg"
  description = "lks vpc serverless sg"
  vpc_id = aws_vpc.lks-vpc-serverless.id

  tags = {
    Name = "lks_vpc_sg"
  }
}

resource "aws_vpc_security_group_egress_rule" "vpc_sg_egress" {
  security_group_id = aws_security_group.lks-vpc-sg.id
  cidr_ipv6 = aws_vpc.lks-vpc-serverless.ipv6_cidr_block
  
  ip_protocol = "-1"
}

resource "aws_internet_gateway" "igw" {
    vpc_id = aws_vpc.lks-vpc-serverless.id
    
    tags = {
        Name = "main"
    }
}

resource "aws_route_table" "route-table-public" {
    vpc_id = aws_vpc.lks-vpc-serverless.id
    
}
#igw route
resource "aws_route" "public-ipv4" {
    route_table_id         = aws_route_table.route-table-public.id
    destination_cidr_block = "0.0.0.0/0"
    gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route" "public-ipv6" {
    route_table_id              = aws_route_table.route-table-public.id
    destination_ipv6_cidr_block = "::/0"
    gateway_id                  = aws_internet_gateway.igw.id
}

resource "aws_route_table" "route-table-private" {
    vpc_id = aws_vpc.lks-vpc-serverless.id
}

resource "aws_route_table_association" "rta-public-1" {
  subnet_id = aws_subnet.lks-vpc-serverless-subnet-public-1.id
  route_table_id = aws_route_table.route-table-public.id
}

resource "aws_route_table_association" "rta-public-2" {
  subnet_id = aws_subnet.lks-vpc-serverless-subnet-public-2.id
  route_table_id = aws_route_table.route-table-public.id
}

resource "aws_route_table_association" "rta-private-1" {  
 subnet_id  = aws_subnet.lks-vpc-serverless-subnet-private-1.id
  route_table_id = aws_route_table.route-table-private.id
}

resource "aws_route_table_association" "rta-private-2" {
  subnet_id = aws_subnet.lks-vpc-serverless-subnet-private-2.id
  route_table_id = aws_route_table.route-table-private.id
}

#lambda security group
resource "aws_security_group" "lks-sg-lambda" {
    name = "lks-sg-lambda"
    description = "security group for lambda function"
    vpc_id = aws_vpc.lks-vpc-serverless.id
}

resource "aws_vpc_security_group_egress_rule" "sg-lambda-egress-ipv4" {
    security_group_id = aws_security_group.lks-sg-lambda.id
    cidr_ipv4 = "0.0.0.0/0"
    ip_protocol = "-1"
}
resource "aws_vpc_security_group_egress_rule" "sg-lambda-egress-ipv6" {
    security_group_id = aws_security_group.lks-sg-lambda.id
    cidr_ipv6 = "::/0"
    ip_protocol = "-1"
}
#rds security group
resource "aws_security_group" "lks-sg-rds" {
    name = "lks-sg-rds"
    description = "security group for rds" 
    vpc_id = aws_vpc.lks-vpc-serverless.id
}

resource "aws_vpc_security_group_ingress_rule" "sg-rds-ingress" {
    security_group_id = aws_security_group.lks-sg-rds.id
    referenced_security_group_id = aws_security_group.lks-sg-lambda.id
    ip_protocol = "tcp"
    from_port = 5432
    to_port  = 5432
}

#vpc endpoint security group
resource "aws_security_group" "lks-sg-vpc-endpoint" {
    name = "lks-sg-vpc-endpoint"
    description = "security group for vpc endpoint"
    vpc_id = aws_vpc.lks-vpc-serverless.id
}

resource "aws_vpc_security_group_ingress_rule" "sg-vpc-endpoint-ingress-http" {
    security_group_id = aws_security_group.lks-sg-vpc-endpoint.id
    cidr_ipv4 = "20.1.0.0/20"
    ip_protocol = "tcp"
    from_port = 8080
    to_port = 8080
}

resource "aws_vpc_security_group_ingress_rule" "sg-vpc-endpoint-ingress-https" {
    security_group_id = aws_security_group.lks-sg-vpc-endpoint.id
    cidr_ipv4 = "20.1.0.0/20"
    ip_protocol = "tcp"
    from_port = 80
    to_port = 80
}

data "aws_vpc_endpoint" "lks-s3-endpoints" {
    vpc_id = aws_vpc.lks-vpc-serverless.id
    service_name = "com.amazonaws.us-east-1.s3"
}

data "aws_vpc_endpoint" "lks-eventbridge-endpoints" {
    vpc_id = aws_vpc.lks-vpc-serverless.id
    service_name = "com.amazonaws.us-east-1.events"
}

data "aws_vpc_endpoint" "lks-steps-endpoints" {
    vpc_id = aws_vpc.lks-vpc-serverless.id
    service_name = "com.amazonaws.us-east-1.states"
}

data "aws_vpc_endpoint" "lks-sns-endpoints" {
    vpc_id = aws_vpc.lks-vpc-serverless.id
    service_name = "com.amazonaws.us-east-1.sns"
}

resource "aws_s3_bucket" "lks-orders-riendra-2026" {
    bucket = "lks-orders"
}

resource "aws_s3_bucket_lifecycle_configuration" "lks-orders-config" {
    bucket = aws_s3_bucket.lks-orders-riendra-2026.id
    
    rule {
        id = ""
        
        expiration {
            days =         
        }
        filter {
        
            and {
            
            }
        }
    }
    status = "Enabled"
    
    
    transition {
        days = 90
        storage_class = "GLACIER"
    }
}
resource "aws_s3_bucket_intelligent_tiering_configuration" "lks-orders-tiering" {
    bucket = aws_s3_bucket.lks-orders-riendra-2026.id
    name = "EntireBucket"
    tiering {
        
    }
}

resource "aws_s3_bucket_versioning" "versioning-lks-orders" {
    bucket = aws_s3_bucket.lks-orders-riendra-2026.id
    versioning_configuration {
        status = "Enabled"
    }
}







