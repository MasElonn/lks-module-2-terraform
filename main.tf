terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}
data "aws_availability_zones" "available" {
}

resource "aws_vpc" "lks-vpc-serverless" {
  cidr_block                       = "20.1.0.0/20"
  assign_generated_ipv6_cidr_block = true
  enable_dns_hostnames             = true
  enable_dns_support               = true
}

resource "aws_subnet" "lks-public-subnet-1" {
  vpc_id                          = aws_vpc.lks-vpc-serverless.id
  cidr_block                      = "20.1.0.0/25"
  ipv6_cidr_block                 = cidrsubnet(aws_vpc.lks-vpc-serverless.ipv6_cidr_block, 8, 0)
  assign_ipv6_address_on_creation = true
  map_public_ip_on_launch         = true
  availability_zone               = data.aws_availability_zones.available.names[0]
}
resource "aws_subnet" "lks-public-subnet-2" {
  vpc_id                          = aws_vpc.lks-vpc-serverless.id
  cidr_block                      = "20.1.1.0/25"
  map_public_ip_on_launch         = true
  ipv6_cidr_block                 = cidrsubnet(aws_vpc.lks-vpc-serverless.ipv6_cidr_block, 8, 1)
  assign_ipv6_address_on_creation = true
  availability_zone               = data.aws_availability_zones.available.names[1]
}

resource "aws_subnet" "lks-private-subnet-1" {
  vpc_id                          = aws_vpc.lks-vpc-serverless.id
  cidr_block                      = "20.1.11.0/25"
  ipv6_cidr_block                 = cidrsubnet(aws_vpc.lks-vpc-serverless.ipv6_cidr_block, 8, 2)
  assign_ipv6_address_on_creation = true
  availability_zone               = data.aws_availability_zones.available.names[0]
}

resource "aws_subnet" "lks-private-subnet-2" {
  vpc_id                          = aws_vpc.lks-vpc-serverless.id
  cidr_block                      = "20.1.12.0/25"
  ipv6_cidr_block                 = cidrsubnet(aws_vpc.lks-vpc-serverless.ipv6_cidr_block, 8, 3)
  assign_ipv6_address_on_creation = true
  availability_zone               = data.aws_availability_zones.available.names[1]
}

resource "aws_egress_only_internet_gateway" "lks-egress-igw-ipv6" {
  vpc_id = aws_vpc.lks-vpc-serverless.id
}

resource "aws_internet_gateway" "lks-igw" {
  vpc_id = aws_vpc.lks-vpc-serverless.id
}

resource "aws_eip" "lks-nat-eip" {
  domain = "vpc"
}
resource "aws_nat_gateway" "lks-nat" {
  allocation_id = aws_eip.lks-nat-eip.id
  subnet_id     = aws_subnet.lks-public-subnet-1.id
}

resource "aws_route_table" "lks-public-rt" {
  vpc_id = aws_vpc.lks-vpc-serverless.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lks-igw.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_egress_only_internet_gateway.lks-egress-igw-ipv6.id
  }
}


resource "aws_route_table" "lks-private-rt" {
  vpc_id = aws_vpc.lks-vpc-serverless.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.lks-nat.id
  }

}

resource "aws_route_table_association" "lks-public-rta" {
  count          = 2
  subnet_id      = [aws_subnet.lks-public-subnet-1.id, aws_subnet.lks-public-subnet-2.id][count.index]
  route_table_id = aws_route_table.lks-public-rt.id
}
resource "aws_route_table_association" "lks-private-rta" {
  count          = 2
  subnet_id      = [aws_subnet.lks-private-subnet-1.id, aws_subnet.lks-private-subnet-2.id][count.index]
  route_table_id = aws_route_table.lks-private-rt.id
}

resource "aws_security_group" "lks-sg-lambda" {
  name        = "lks-sg-lambda"
  description = "Security Group For Lambda"
  vpc_id      = aws_vpc.lks-vpc-serverless.id

}

resource "aws_vpc_security_group_egress_rule" "lambda-all" {
  security_group_id = aws_security_group.lks-sg-lambda.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_security_group" "lks-sg-rds" {
  name        = "lks-sg-rds"
  description = "Security Group For RDS"
  vpc_id      = aws_vpc.lks-vpc-serverless.id
}
resource "aws_vpc_security_group_ingress_rule" "lks-sg-rds-rule" {
  security_group_id = aws_security_group.lks-sg-rds.id

  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.lks-sg-lambda.id
}

resource "aws_security_group" "lks-sg-vpc-endpoint" {
  name        = "lks-sg-vpc-endpoint"
  description = "Security Group For VPC Endpoint"
  vpc_id      = aws_vpc.lks-vpc-serverless.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["20.1.0.0/20"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["20.1.0.0/20"]
  }

}
resource "aws_vpc_endpoint" "lks-s3-endpoints" {
  vpc_id            = aws_vpc.lks-vpc-serverless.id
  service_name      = "com.amazonaws.us-east-1.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.lks-private-rt.id]
}

resource "aws_vpc_endpoint" "lks-eventbridge-endpoints" {
  vpc_id              = aws_vpc.lks-vpc-serverless.id
  service_name        = "com.amazonaws.us-east-1.events"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.lks-private-subnet-1.id, aws_subnet.lks-private-subnet-2.id]
  security_group_ids  = [aws_security_group.lks-sg-vpc-endpoint.id]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "lks-steps-endpoints" {
  vpc_id              = aws_vpc.lks-vpc-serverless.id
  service_name        = "com.amazonaws.us-east-1.states"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.lks-private-subnet-1.id, aws_subnet.lks-private-subnet-2.id]
  security_group_ids  = [aws_security_group.lks-sg-vpc-endpoint.id]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "lks-sns-endpoints" {
  vpc_id              = aws_vpc.lks-vpc-serverless.id
  service_name        = "com.amazonaws.us-east-1.sns"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.lks-private-subnet-1.id, aws_subnet.lks-private-subnet-2.id]
  security_group_ids  = [aws_security_group.lks-sg-vpc-endpoint.id]
  private_dns_enabled = true
}

resource "aws_s3_bucket" "lks-order-riendra-2026" {
  bucket = "lks-order-riendra-2026"
}

resource "aws_s3_bucket_versioning" "orders" {
  bucket = aws_s3_bucket.lks-order-riendra-2026.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "s3-order-lifecycle" {
  bucket     = aws_s3_bucket.lks-order-riendra-2026.id
  depends_on = [aws_s3_bucket_versioning.orders]

  rule {
    id     = "config"
    status = "Enabled"
    filter {}

    transition {
      storage_class = "INTELLIGENT_TIERING"
      days          = 30
    }

    transition {
      storage_class = "GLACIER"
      days          = 90
    }

    expiration {
      days = 365
    }

    noncurrent_version_expiration { noncurrent_days = 30 }
  }
}

resource "aws_s3_bucket_cors_configuration" "s3-order-cors" {
  bucket = aws_s3_bucket.lks-order-riendra-2026.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT", "POST", "GET", "DELETE"]
    allowed_origins = ["https://s3-website-test.hashicorp.com"]
  }
}

resource "aws_s3_bucket" "lks-logs-riendra-2026" {
  bucket = "lks-logs-riendra-2026"
}

resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.lks-logs-riendra-2026.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "s3-logs-lifecycle" {
  bucket     = aws_s3_bucket.lks-logs-riendra-2026.id
  depends_on = [aws_s3_bucket_versioning.logs]

  rule {
    id     = "config"
    status = "Enabled"
    filter {}

    transition {
      storage_class = "INTELLIGENT_TIERING"
      days          = 7
    }

    expiration {
      days = 90
    }
    noncurrent_version_expiration { noncurrent_days = 30 }
  }
}

resource "aws_db_instance" "lks-rds-orders" {
  allocated_storage = 20
  db_name           = "orders"
  engine            = "postgres"
  engine_version    = "15"
  instance_class    = "db.t3.micro"
  username          = "dbadmin"
  password          = "TechnoCloud2026!"
  storage_type      = "gp3"

  db_subnet_group_name    = aws_db_subnet_group.lks-rds-subnet.name
  publicly_accessible     = false
  vpc_security_group_ids  = [aws_security_group.lks-sg-rds.id]
  backup_retention_period = 1
  skip_final_snapshot     = true
}
resource "aws_db_subnet_group" "lks-rds-subnet" {
  name       = "lks-rds-orders"
  subnet_ids = [aws_subnet.lks-private-subnet-1.id, aws_subnet.lks-private-subnet-2.id]
}
resource "aws_lambda_layer_version" "lks-lambda-layer" {
  filename   = "${path.module}/wakawaka/lambda/layers.zip"
  layer_name = "lks-lambda-layer"
}


data "archive_file" "lambda-db-init-file" {
  type        = "zip"
  source_file = "${path.module}/wakawaka/lambda/init_database/lambda_function.py"
  output_path = "${path.module}/wakawaka/lambda/init_database/lambda_function.zip"
}
resource "aws_lambda_function" "lks-lambda-init-db" {
  filename      = data.archive_file.lambda-db-init-file.output_path
  function_name = "lks-lambda-init-db"
  role          = "arn:aws:iam::436095652486:role/LabRole"
  handler       = "lambda_function.lambda_handler"
  code_sha256   = data.archive_file.lambda-db-init-file.output_base64sha256
  layers        = [aws_lambda_layer_version.lks-lambda-layer.arn]

  memory_size = 512
  timeout     = 300
  runtime     = "python3.11"

  vpc_config {
    subnet_ids         = [aws_subnet.lks-private-subnet-1.id, aws_subnet.lks-private-subnet-2.id]
    security_group_ids = [aws_security_group.lks-sg-lambda.id]
  }
  environment {
    variables = {
      DB_HOST     = aws_db_instance.lks-rds-orders.address
      DB_PORT     = "5432"
      DB_NAME     = "orders"
      DB_USER     = "dbadmin"
      DB_PASSWORD = "TechnoCloud2026!"
    }
  }
}

action "aws_lambda_invoke" "invoke-db-func" {
  config {
    function_name = aws_lambda_function.lks-lambda-init-db.function_name
    payload       = jsonencode({})
  }
}

data "archive_file" "lambda-order-file" {
  type        = "zip"
  source_file = "${path.module}/wakawaka/lambda/order_management/lambda_function.py"
  output_path = "${path.module}/wakawaka/lambda/order_management/lambda_function.zip"
}
resource "aws_lambda_function" "lks-lambda-order-management" {
  filename      = data.archive_file.lambda-order-file.output_path
  function_name = "lks-lambda-order-management"
  role          = "arn:aws:iam::436095652486:role/LabRole"
  handler       = "lambda_function.lambda_handler"
  code_sha256   = data.archive_file.lambda-order-file.output_base64sha256
  layers        = [aws_lambda_layer_version.lks-lambda-layer.arn]

  memory_size = 512
  timeout     = 30

  runtime = "python3.11"

  vpc_config {
    subnet_ids         = [aws_subnet.lks-private-subnet-1.id, aws_subnet.lks-private-subnet-2.id]
    security_group_ids = [aws_security_group.lks-sg-lambda.id]
  }

  environment {
    variables = {
      DB_HOST           = aws_db_instance.lks-rds-orders.address
      DB_PORT           = "5432"
      DB_NAME           = "orders"
      DB_USER           = "dbadmin"
      DB_PASSWORD       = "TechnoCloud2026!"
      S3_BUCKET         = aws_s3_bucket.lks-order-riendra-2026.bucket
      STATE_MACHINE_ARN = "arn:aws:states:us-east-1:436095652486:stateMachine:lks-stepfunctions-workflow"
    }
  }

}

data "archive_file" "lambda-process-file" {
  type        = "zip"
  source_file = "${path.module}/wakawaka/lambda/process_payment/lambda_function.py"
  output_path = "${path.module}/wakawaka/lambda/process_payment/lambda_function.zip"
}

resource "aws_lambda_function" "lks-lambda-process-payment" {
  filename      = data.archive_file.lambda-process-file.output_path
  function_name = "lks-lambda-process-payment"
  role          = "arn:aws:iam::436095652486:role/LabRole"
  handler       = "lambda_function.lambda_handler"
  code_sha256   = data.archive_file.lambda-order-file.output_base64sha256
  layers        = [aws_lambda_layer_version.lks-lambda-layer.arn]

  memory_size = 512
  timeout     = 30

  runtime = "python3.11"

  vpc_config {
    subnet_ids         = [aws_subnet.lks-private-subnet-1.id, aws_subnet.lks-private-subnet-2.id]
    security_group_ids = [aws_security_group.lks-sg-lambda.id]
  }

  environment {
    variables = {
      ORDER_MANAGEMENT_FUNCTION = aws_lambda_function.lks-lambda-order-management.arn
      NOTIFICATION_FUNCTION     = aws_sns_topic.lks-sns-order-notifications.arn

    }
  }

}

data "archive_file" "lambda-update-inventory-file" {
  type        = "zip"
  source_file = "${path.module}/wakawaka/lambda/update_inventory/lambda_function.py"
  output_path = "${path.module}/wakawaka/lambda/update_inventory/lambda_function.zip"
}

resource "aws_lambda_function" "lks-lambda-update-inventory" {
  filename      = data.archive_file.lambda-update-inventory-file.output_path
  function_name = "lks-lambda-update-inventory"
  role          = "arn:aws:iam::436095652486:role/LabRole"
  handler       = "lambda_function.lambda_handler"
  code_sha256   = data.archive_file.lambda-update-inventory-file.output_base64sha256
  layers        = [aws_lambda_layer_version.lks-lambda-layer.arn]

  memory_size = 256
  timeout     = 45

  runtime = "python3.11"

  vpc_config {
    subnet_ids         = [aws_subnet.lks-private-subnet-1.id, aws_subnet.lks-private-subnet-2.id]
    security_group_ids = [aws_security_group.lks-sg-lambda.id]
  }

  environment {
    variables = {
      DB_HOST     = aws_db_instance.lks-rds-orders.address
      DB_PORT     = "5432"
      DB_NAME     = "orders"
      DB_USER     = "dbadmin"
      DB_PASSWORD = "TechnoCloud2026!"
      S3_BUCKET   = aws_s3_bucket.lks-order-riendra-2026.bucket

    }
  }
}



data "archive_file" "lambda-generate-file" {
  type        = "zip"
  source_file = "${path.module}/wakawaka/lambda/generate_report/lambda_function.py"
  output_path = "${path.module}/wakawaka/lambda/generate_report/lambda_function.zip"
}

resource "aws_lambda_function" "lks-lambda-generate-report" {
  filename      = data.archive_file.lambda-generate-file.output_path
  function_name = "lks-lambda-generate-report"
  role          = "arn:aws:iam::436095652486:role/LabRole"
  handler       = "lambda_function.lambda_handler"
  code_sha256   = data.archive_file.lambda-generate-file.output_base64sha256
  layers        = [aws_lambda_layer_version.lks-lambda-layer.arn]

  memory_size = 256
  timeout     = 45

  runtime = "python3.11"

  vpc_config {
    subnet_ids         = [aws_subnet.lks-private-subnet-1.id, aws_subnet.lks-private-subnet-2.id]
    security_group_ids = [aws_security_group.lks-sg-lambda.id]
  }

  environment {
    variables = {
      DB_HOST     = aws_db_instance.lks-rds-orders.address
      DB_PORT     = "5432"
      DB_NAME     = "orders"
      DB_USER     = "dbadmin"
      DB_PASSWORD = "TechnoCloud2026!"
      S3_BUCKET   = aws_s3_bucket.lks-order-riendra-2026.bucket

    }
  }
}


data "archive_file" "lambda-notification-file" {
  type        = "zip"
  source_file = "${path.module}/wakawaka/lambda/send_notification/lambda_function.py"
  output_path = "${path.module}/wakawaka/lambda/send_notification/lambda_function.zip"
}

resource "aws_lambda_function" "lks-lambda-send-notification" {
  filename      = data.archive_file.lambda-notification-file.output_path
  function_name = "lks-lambda-send-notification"
  role          = "arn:aws:iam::436095652486:role/LabRole"
  handler       = "lambda_function.lambda_handler"
  code_sha256   = data.archive_file.lambda-notification-file.output_base64sha256
  layers        = [aws_lambda_layer_version.lks-lambda-layer.arn]
  
  memory_size = 256
  timeout     = 45

  runtime = "python3.11"

  vpc_config {
    subnet_ids         = [aws_subnet.lks-private-subnet-1.id, aws_subnet.lks-private-subnet-2.id]
    security_group_ids = [aws_security_group.lks-sg-lambda.id]
  }

  environment {
    variables = {
      DB_HOST     = aws_db_instance.lks-rds-orders.address
      DB_PORT     = "5432"
      DB_NAME     = "orders"
      DB_USER     = "dbadmin"
      DB_PASSWORD = "TechnoCloud2026!"
      S3_BUCKET   = aws_s3_bucket.lks-order-riendra-2026.bucket
      NOTIFICATION_FUNCTION     = aws_sns_topic.lks-sns-order-notifications.arn

    }
  }
}

resource "aws_sns_topic" "lks-sns-order-notifications" {
  name = "lks-sns-order-notifications"
}

resource "aws_api_gateway_rest_api" "lks-api-orders" {
  name                 = "lks-api-orders"
  security_policy      = "SecurityPolicy_TLS13_1_3_2025_09"
  endpoint_access_mode = "BASIC"

  endpoint_configuration {
    types           = ["REGIONAL"]
    ip_address_type = "dualstack"
  }
}

resource "aws_api_gateway_resource" "orders" {
  rest_api_id = aws_api_gateway_rest_api.lks-api-orders.id
  parent_id   = aws_api_gateway_rest_api.lks-api-orders.root_resource_id
  path_part   = "orders"
}

resource "aws_api_gateway_resource" "order-id" {
  rest_api_id = aws_api_gateway_rest_api.lks-api-orders.id
  parent_id   = aws_api_gateway_resource.orders.id
  path_part   = "{id}"
}

resource "aws_api_gateway_resource" "status" {
  rest_api_id = aws_api_gateway_rest_api.lks-api-orders.id
  parent_id   = aws_api_gateway_rest_api.lks-api-orders.root_resource_id
  path_part   = "status"
}

resource "aws_api_gateway_resource" "status-id" {
  rest_api_id = aws_api_gateway_rest_api.lks-api-orders.id
  parent_id   = aws_api_gateway_resource.status.id
  path_part   = "{id}"
}

resource "aws_api_gateway_resource" "customers" {
  rest_api_id = aws_api_gateway_rest_api.lks-api-orders.id
  parent_id   = aws_api_gateway_rest_api.lks-api-orders.root_resource_id
  path_part   = "customers"
}

resource "aws_api_gateway_resource" "products" {
  rest_api_id = aws_api_gateway_rest_api.lks-api-orders.id
  parent_id   = aws_api_gateway_rest_api.lks-api-orders.root_resource_id
  path_part   = "products"
}

locals {
  cors_resources = {
    orders    = aws_api_gateway_resource.orders.id
    order-id  = aws_api_gateway_resource.order-id.id
    status-id = aws_api_gateway_resource.status-id.id
    customers = aws_api_gateway_resource.customers.id
    products  = aws_api_gateway_resource.products.id
  }
}

resource "aws_api_gateway_method" "options" {
  for_each         = local.cors_resources
  rest_api_id      = aws_api_gateway_rest_api.lks-api-orders.id
  resource_id      = each.value
  http_method      = "OPTIONS"
  authorization    = "NONE"
  api_key_required = false
}

resource "aws_api_gateway_integration" "options" {
  for_each    = local.cors_resources
  rest_api_id = aws_api_gateway_rest_api.lks-api-orders.id
  resource_id = each.value
  http_method = aws_api_gateway_method.options[each.key].http_method
  type        = "MOCK"
  request_templates = {
    "application/json" = jsonencode({ statusCode = 200 })
  }
}

resource "aws_api_gateway_method_response" "options" {
  for_each    = local.cors_resources
  rest_api_id = aws_api_gateway_rest_api.lks-api-orders.id
  resource_id = each.value
  http_method = aws_api_gateway_method.options[each.key].http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Headers" = true
  }
}

resource "aws_api_gateway_integration_response" "options" {
  for_each    = local.cors_resources
  rest_api_id = aws_api_gateway_rest_api.lks-api-orders.id
  resource_id = each.value
  http_method = aws_api_gateway_method.options[each.key].http_method
  status_code = aws_api_gateway_method_response.options[each.key].status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,PUT,DELETE,OPTIONS'"
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,x-api-key,Authorization'"
  }
  depends_on = [aws_api_gateway_integration.options]
}

# CORS headers on gateway-generated errors (bad key, throttling, etc.)
resource "aws_api_gateway_gateway_response" "default-4xx" {
  rest_api_id   = aws_api_gateway_rest_api.lks-api-orders.id
  response_type = "DEFAULT_4XX"
  response_parameters = {
    "gatewayresponse.header.Access-Control-Allow-Origin"  = "'*'"
    "gatewayresponse.header.Access-Control-Allow-Headers" = "'Content-Type,x-api-key,Authorization'"
  }
}

resource "aws_api_gateway_gateway_response" "default-5xx" {
  rest_api_id   = aws_api_gateway_rest_api.lks-api-orders.id
  response_type = "DEFAULT_5XX"
  response_parameters = {
    "gatewayresponse.header.Access-Control-Allow-Origin"  = "'*'"
    "gatewayresponse.header.Access-Control-Allow-Headers" = "'Content-Type,x-api-key,Authorization'"
  }
}

locals {
  api_routes = {
    orders-get      = { resource_id = aws_api_gateway_resource.orders.id, method = "GET" }
    orders-post     = { resource_id = aws_api_gateway_resource.orders.id, method = "POST" }
    order-id-get    = { resource_id = aws_api_gateway_resource.order-id.id, method = "GET" }
    order-id-put    = { resource_id = aws_api_gateway_resource.order-id.id, method = "PUT" }
    order-id-delete = { resource_id = aws_api_gateway_resource.order-id.id, method = "DELETE" }
    status-id-get   = { resource_id = aws_api_gateway_resource.status-id.id, method = "GET" }
    customers-get   = { resource_id = aws_api_gateway_resource.customers.id, method = "GET" }
    products-get    = { resource_id = aws_api_gateway_resource.products.id, method = "GET" }
  }
}

resource "aws_api_gateway_method" "routes" {
  for_each         = local.api_routes
  rest_api_id      = aws_api_gateway_rest_api.lks-api-orders.id
  resource_id      = each.value.resource_id
  http_method      = each.value.method
  authorization    = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_integration" "routes" {
  for_each                = local.api_routes
  rest_api_id             = aws_api_gateway_rest_api.lks-api-orders.id
  resource_id             = each.value.resource_id
  http_method             = aws_api_gateway_method.routes[each.key].http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.lks-lambda-order-management.invoke_arn
}

resource "aws_lambda_permission" "apigw-order-mgmt" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lks-lambda-order-management.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.lks-api-orders.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "orders" {
  rest_api_id = aws_api_gateway_rest_api.lks-api-orders.id

  triggers = {
    redeployment = sha1(jsonencode([
      [for m in aws_api_gateway_method.routes : m.id],
      [for i in aws_api_gateway_integration.routes : i.id],
      [for m in aws_api_gateway_method.options : m.id],
      [for i in aws_api_gateway_integration.options : i.id],
      [for r in aws_api_gateway_integration_response.options : r.id],
      aws_api_gateway_gateway_response.default-4xx.id,
      aws_api_gateway_gateway_response.default-5xx.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "production" {
  rest_api_id   = aws_api_gateway_rest_api.lks-api-orders.id
  deployment_id = aws_api_gateway_deployment.orders.id
  stage_name    = "production"
}


resource "aws_api_gateway_api_key" "lks-api-key" {
  name    = "lks-api-key"
  enabled = true
}

resource "aws_api_gateway_usage_plan" "lks-usage-plan" {
  name = "lks-usage-plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.lks-api-orders.id
    stage  = aws_api_gateway_stage.production.stage_name
  }

  throttle_settings {
    rate_limit  = 1000
    burst_limit = 2000
  }

  quota_settings {
    limit  = 100000
    period = "MONTH"
  }
}

resource "aws_api_gateway_usage_plan_key" "lks-usage-plan-key" {
  key_id        = aws_api_gateway_api_key.lks-api-key.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.lks-usage-plan.id
}

output "api_invoke_url" {
  value = aws_api_gateway_stage.production.invoke_url
}