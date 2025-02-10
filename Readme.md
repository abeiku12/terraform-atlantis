Features of this Deployment:
✅ Deploys Atlantis on an EC2 instance (Amazon Linux 2).
✅ Creates an IAM role for Atlantis with Terraform state access.
✅ Configures S3 for Terraform state storage and DynamoDB for state locking.
✅ Uses Auto Scaling Group (ASG) with a Load Balancer for HA.
✅ Supports GitHub Webhooks for triggering Atlantis on PRs.

This Terraform script will:
✅ Create an S3 bucket for Terraform state storage.
✅ Set up DynamoDB for state locking.
✅ Create an IAM role with least privilege access.
✅ Deploy Atlantis on an EC2 instance, running as a Docker container.
✅ Open port 4141 for GitHub/GitLab webhooks.

