provider "aws" {
  region = "us-west-2"
}

# S3 Bucket for Terraform State
resource "aws_s3_bucket" "terraform_state" {
  bucket = "your-terraform-state-bucket"
  acl    = "private"
}

resource "aws_dynamodb_table" "terraform_lock" {
  name         = "terraform-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

# IAM Role for Atlantis
resource "aws_iam_role" "atlantis" {
  name = "atlantis-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_policy" "atlantis_policy" {
  name        = "atlantis-policy"
  description = "Policy for Atlantis to access Terraform state"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket", "s3:GetObject", "s3:PutObject"
      ],
      "Resource": "arn:aws:s3:::your-terraform-state-bucket/*"
    },
    {
      "Effect": "Allow",
      "Action": ["dynamodb:*"],
      "Resource": "arn:aws:dynamodb:us-west-2:123456789012:table/terraform-lock"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "attach_atlantis_policy" {
  role       = aws_iam_role.atlantis.name
  policy_arn = aws_iam_policy.atlantis_policy.arn
}

# Security Group
resource "aws_security_group" "atlantis_sg" {
  name        = "atlantis-sg"
  description = "Allow SSH and Atlantis Webhook"
  vpc_id      = "your-vpc-id"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Restrict this in production
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # HTTPS access
  }
}

# Load Balancer for HTTPS
resource "aws_lb" "atlantis_lb" {
  name               = "atlantis-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.atlantis_sg.id]
  subnets            = ["subnet-123456", "subnet-789012"]
}

resource "aws_lb_listener" "https_listener" {
  load_balancer_arn = aws_lb.atlantis_lb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = "arn:aws:acm:us-west-2:123456789012:certificate/your-cert-id"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.atlantis_tg.arn
  }
}

resource "aws_lb_target_group" "atlantis_tg" {
  name     = "atlantis-tg"
  port     = 4141
  protocol = "HTTP"
  vpc_id   = "your-vpc-id"
}

# ECS Cluster for Atlantis
resource "aws_ecs_cluster" "atlantis_cluster" {
  name = "atlantis-cluster"
}

resource "aws_ecs_task_definition" "atlantis_task" {
  family                   = "atlantis"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"

  container_definitions = <<TASK_DEFINITION
[
  {
    "name": "atlantis",
    "image": "runatlantis/atlantis",
    "cpu": 256,
    "memory": 512,
    "portMappings": [
      {
        "containerPort": 4141,
        "hostPort": 4141
      }
    ],
    "environment": [
      { "name": "ATLANTIS_GH_USER", "value": "your-github-user" },
      { "name": "ATLANTIS_GH_TOKEN", "value": "your-github-token" }
    ]
  }
]
TASK_DEFINITION
}

resource "aws_ecs_service" "atlantis_service" {
  name            = "atlantis-service"
  cluster         = aws_ecs_cluster.atlantis_cluster.id
  task_definition = aws_ecs_task_definition.atlantis_task.arn
  launch_type     = "FARGATE"
  desired_count   = 1
  network_configuration {
    subnets = ["subnet-123456", "subnet-789012"]
    security_groups = [aws_security_group.atlantis_sg.id]
  }
}

