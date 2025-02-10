terraform {
  backend "s3" {
    bucket         = "your-s3-bucket"
    key            = "terraform/atlantis/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-lock"
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_iam_role" "atlantis" {
  name = "atlantis-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_policy" "atlantis_policy" {
  name        = "AtlantisPolicy"
  description = "Least privilege for Atlantis"
  policy      = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:PutObject"
        ],
        Effect   = "Allow",
        Resource = "arn:aws:s3:::your-s3-bucket/*"
      },
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem"
        ],
        Effect   = "Allow",
        Resource = "arn:aws:dynamodb:us-east-1:your-account-id:table/terraform-lock"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_atlantis_policy" {
  policy_arn = aws_iam_policy.atlantis_policy.arn
  role       = aws_iam_role.atlantis.name
}

resource "aws_launch_template" "atlantis" {
  name_prefix   = "atlantis-"
  image_id      = "ami-0abcdef1234567890" # Use a valid Ubuntu or Amazon Linux AMI
  instance_type = "t3.medium"

  iam_instance_profile {
    name = aws_iam_role.atlantis.name
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              apt update && apt install -y docker
              systemctl start docker
              docker run --name atlantis -d -p 4141:4141 runatlantis/atlantis
              EOF
            )
}

resource "aws_autoscaling_group" "atlantis" {
  min_size             = 1
  desired_capacity     = 2
  max_size             = 3
  vpc_zone_identifier  = ["subnet-12345678", "subnet-87654321"]
  launch_template {
    id      = aws_launch_template.atlantis.id
    version = "$Latest"
  }
}

resource "aws_lb" "atlantis" {
  name               = "atlantis-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = ["sg-12345678"]
  subnets           = ["subnet-12345678", "subnet-87654321"]
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.atlantis.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.atlantis.arn
  }
}

resource "aws_lb_target_group" "atlantis" {
  name     = "atlantis-tg"
  port     = 4141
  protocol = "HTTP"
  vpc_id   = "vpc-12345678"
}

resource "aws_autoscaling_attachment" "atlantis" {
  autoscaling_group_name = aws_autoscaling_group.atlantis.id
  lb_target_group_arn    = aws_lb_target_group.atlantis.arn
}

resource "aws_cloudwatch_log_group" "atlantis" {
  name              = "/aws/atlantis"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_stream" "atlantis" {
  log_group_name = aws_cloudwatch_log_group.atlantis.name
  name          = "atlantis-logs"
}

resource "aws_eks_cluster" "eks" {
  name     = "atlantis-eks"
  role_arn = aws_iam_role.atlantis.arn

  vpc_config {
    subnet_ids = ["subnet-12345678", "subnet-87654321"]
  }
}

resource "aws_eks_node_group" "worker_nodes" {
  cluster_name    = aws_eks_cluster.eks.name
  node_group_name = "atlantis-worker-nodes"
  node_role_arn   = aws_iam_role.atlantis.arn
  subnet_ids      = ["subnet-12345678", "subnet-87654321"]
  instance_types  = ["t3.medium"]
  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }
}

resource "kubernetes_cluster_autoscaler" "eks_autoscaler" {
  cluster_name = aws_eks_cluster.eks.name
}

resource "kubernetes_horizontal_pod_autoscaler" "hpa" {
  metadata {
    name = "atlantis-hpa"
  }

  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = "atlantis"
    }
    min_replicas = 1
    max_replicas = 5
    metrics {
      type = "Resource"
      resource {
        name  = "cpu"
        target_average_utilization = 50
      }
    }
  }
}

resource "kubernetes_vertical_pod_autoscaler" "vpa" {
  metadata {
    name = "atlantis-vpa"
  }

  spec {
    target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = "atlantis"
    }
    update_policy {
      update_mode = "Auto"
    }
  }
}
