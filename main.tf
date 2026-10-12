# this project is a testing using a provider aws
# with vpc/apigateway/sqs/lambda/rds, and terraform version 1.7.6
# provider aws version 6.68.0

# ==========================================
# 1. SQS - Dead Letter Queue
# ==========================================

resource "aws_sqs_queue" "deadletter" {
  name                      = "terraform-test-dlq"
  message_retention_seconds = 1209600

  tags = {
    Environment = "testing"
    Purpose     = "dead-letter-queue"
  }
}

# ==========================================
# 2. SQS - Main Queue
# ==========================================

resource "aws_sqs_queue" "main" {
  name                      = "terraform-test-queue"
  delay_seconds             = 0
  max_message_size          = 262144
  message_retention_seconds = 86400
  receive_wait_time_seconds = 10

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.deadletter.arn
    maxReceiveCount     = 4
  })

  tags = {
    Environment = "testing"
    Purpose     = "main-queue"
  }
}

# ==========================================
# 3. SQS - Queue Policy
# Deny requests without HTTPS
# ==========================================

resource "aws_sqs_queue_policy" "main" {
  queue_url = aws_sqs_queue.main.url

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "sqs:*"
        Resource  = aws_sqs_queue.main.arn

        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# ==========================================
# 4. IAM Role for Lambda
# ==========================================

resource "aws_iam_role" "lambda" {
  name = "terraform-test-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "lambda.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })
}

# ==========================================
# 5. IAM Permissions
# CloudWatch Logs + SQS
# ==========================================

resource "aws_iam_role_policy" "lambda" {
  name = "terraform-test-lambda-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]

        Resource = "*"
      },
      {
        Effect = "Allow"

        Action = [
          "sqs:SendMessage"
        ]

        Resource = aws_sqs_queue.main.arn
      },
      {
        Effect = "Allow"

        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ChangeMessageVisibility"
        ]

        Resource = aws_sqs_queue.main.arn
      }
    ]
  })
}

# ==========================================
# 6. Lambda Producer
# API Gateway -> Lambda -> SQS
# Requires function.zip
# ==========================================

resource "aws_lambda_function" "producer" {
  filename         = "function.zip"
  function_name    = "terraform-test-producer"
  role             = aws_iam_role.lambda.arn
  handler          = "index.handler"
  runtime          = "python3.12"
  source_code_hash = filebase64sha256("function.zip")

  environment {
    variables = {
      QUEUE_URL = aws_sqs_queue.main.url
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda
  ]

  tags = {
    Environment = "testing"
    Purpose     = "send-messages"
  }
}

# ==========================================
# 7. Lambda Consumer
# SQS -> Lambda
# Requires consumer.zip
# ==========================================

resource "aws_lambda_function" "consumer" {
  filename         = "consumer.zip"
  function_name    = "terraform-test-consumer"
  role             = aws_iam_role.lambda.arn
  handler          = "index.handler"
  runtime          = "python3.12"
  source_code_hash = filebase64sha256("consumer.zip")

  depends_on = [
    aws_iam_role_policy.lambda
  ]

  tags = {
    Environment = "testing"
    Purpose     = "process-messages"
  }
}

# ==========================================
# 8. SQS Event Source Mapping
# Connects the queue to the consumer Lambda
# ==========================================

resource "aws_lambda_event_source_mapping" "sqs" {
  event_source_arn = aws_sqs_queue.main.arn
  function_name    = aws_lambda_function.consumer.arn
  batch_size       = 10
  enabled          = true
}

# ==========================================
# 9. API Gateway HTTP API
# ==========================================

resource "aws_apigatewayv2_api" "http" {
  name          = "terraform-test-http-api"
  protocol_type = "HTTP"

  tags = {
    Environment = "testing"
  }
}

# ==========================================
# 10. API Gateway -> Lambda Integration
# ==========================================

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.producer.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

# ==========================================
# 11. API Gateway Route
# ==========================================

resource "aws_apigatewayv2_route" "messages" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "POST /messages"

  target = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

# ==========================================
# 12. API Gateway Stage
# ==========================================

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true
}

# ==========================================
# 13. Permission for API Gateway to invoke Lambda
# ==========================================

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowApiGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.producer.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}

# ==========================================
# 14. RDS MySQL
# Uses the account's default VPC networking
# when supported by the AWS account.
# ==========================================

variable "db_password" {
  description = "Password for the test database"
  type        = string
  sensitive   = true
}

resource "aws_db_instance" "main" {
  identifier          = "terraform-test-mysql"
  allocated_storage   = 20
  engine              = "mysql"
  engine_version      = "8.0"
  instance_class      = "db.t3.micro"
  db_name             = "testdb"
  username            = "appuser"
  password            = var.db_password
  publicly_accessible = false
  skip_final_snapshot = true

  tags = {
    Environment = "testing"
    Purpose     = "database"
  }
}

# ==========================================
# 15. Outputs
# ==========================================

output "api_endpoint" {
  description = "HTTP API endpoint"
  value       = aws_apigatewayv2_api.http.api_endpoint
}

output "sqs_queue_url" {
  description = "Main SQS queue URL"
  value       = aws_sqs_queue.main.url
}

output "deadletter_queue_arn" {
  description = "Dead Letter Queue ARN"
  value       = aws_sqs_queue.deadletter.arn
}

output "rds_endpoint" {
  description = "MySQL endpoint"
  value       = aws_db_instance.main.endpoint
}
