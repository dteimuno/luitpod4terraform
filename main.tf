provider "aws" {
  region = "us-east-1"

}
# Create S3 bucket for dev environment
resource "aws_s3_bucket" "s3-bucket-dev" {
  bucket = "pod4-bucket-dev"
}

#s3 bucket for storing codepipeline artifacts
resource "aws_s3_bucket" "artifact_bucket" {
  bucket = "pod4-artifact-bucket-luit"
}

# Open up public access to the S3 dev bucket
resource "aws_s3_bucket_public_access_block" "s3_bucket_public_access_block" {
  bucket = aws_s3_bucket.s3-bucket-dev.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# S3 dev Bucket Policy to Allow Public Read Access
resource "aws_s3_bucket_policy" "public_read_policy" {
  bucket = aws_s3_bucket.s3-bucket-dev.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Sid       = "PublicReadGetObject",
      Effect    = "Allow",
      Principal = "*",
      Action    = "s3:GetObject",
      Resource  = "${aws_s3_bucket.s3-bucket-dev.arn}/*"
    }]
  })
}

# Configure static website hosting for the S3 dev bucket
resource "aws_s3_bucket_website_configuration" "static-website" {
  bucket = aws_s3_bucket.s3-bucket-dev.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

# Create S3 bucket for prod environment
resource "aws_s3_bucket" "s3-bucket-prod" {
  bucket = "pod4-bucket-prod"
}

# Open up public access to the S3 prod bucket
resource "aws_s3_bucket_public_access_block" "s3_bucket_public_access_block2" {
  bucket = aws_s3_bucket.s3-bucket-prod.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# S3 prod  Bucket Policy to Allow Public Read Access
resource "aws_s3_bucket_policy" "public_read_policy2" {
  bucket = aws_s3_bucket.s3-bucket-prod.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Sid       = "PublicReadGetObject",
      Effect    = "Allow",
      Principal = "*",
      Action    = "s3:GetObject",
      Resource  = "${aws_s3_bucket.s3-bucket-prod.arn}/*"
    }]
  })
}

# Configure static website hosting for the S3 prod bucket
resource "aws_s3_bucket_website_configuration" "static-website2" {
  bucket = aws_s3_bucket.s3-bucket-prod.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

# Create CloudFront distribution from public S3 bucket
resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.s3-bucket-prod.bucket_regional_domain_name
    origin_id   = aws_s3_bucket.s3-bucket-prod.id

    # Use a public custom origin config instead of OAI
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only" # Can also be "match-viewer" or "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "S3 bucket distribution (Public Access)"
  default_root_object = "index.html"
  retain_on_delete    = true

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_s3_bucket.s3-bucket-prod.id

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
  }

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["US", "CA", "MX"] # Allow access from North America
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}


resource "aws_codepipeline" "pipeline" {
  name     = "static-site-pipeline"
  role_arn = var.CodePipelineServiceRolearn # Change to your existing CodePipeline role

  artifact_store {
    location = aws_s3_bucket.artifact_bucket.id
    type     = "S3"
  }

  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["SourceOutput"]

      configuration = {
        ConnectionArn    = var.ConnectionArn
        FullRepositoryId = var.repository-id
        BranchName       = "main"
      }
    }
  }

  stage {
    name = "Approval"
    action {
      name     = "ManualApproval"
      category = "Approval"
      owner    = "AWS"
      provider = "Manual"
      version  = "1"
      configuration = {
        notification_arn = aws_sns_topic.approval_notifications.arn
      }


    }
  }

  stage {
    name = "Deploy"
    action {
      name     = "DeployToS3"
      category = "Deploy"
      owner    = "AWS"
      provider = "S3"
      version  = "1"

      input_artifacts = ["SourceOutput"] # Ensure it matches the output of the Source stage

      configuration = {
        BucketName = aws_s3_bucket.s3-bucket-prod.bucket # Use .bucket instead of .id
        Extract    = "true"
      }
    }
  }
}

resource "aws_sns_topic" "approval_notifications" {
  name = "approval-notifications"
}
resource "aws_sns_topic_subscription" "approval_subscription" {
  topic_arn = aws_sns_topic.approval_notifications.arn
  protocol  = "email"
  endpoint  = var.email # Replace with your email address
}


