# AWS Infrastructure Setup using Terraform

## Overview
This Terraform configuration sets up an AWS infrastructure that includes:
- Amazon S3 buckets for development and artifact storage
- Public access policies for an S3 bucket
- Static website hosting with CloudFront distribution
- AWS CodePipeline for automated CI/CD deployment triggered by GitHub
- A branching strategy where changes are first deployed to the `dev` branch, approved, and then merged into the `main` branch to trigger the CI/CD pipeline

## AWS Provider Configuration
```hcl
provider "aws" {
  region = "us-east-1"
}
```
This specifies that AWS resources will be deployed in the `us-east-1` region.

## S3 Buckets
### Development S3 Bucket
```hcl
resource "aws_s3_bucket" "s3-bucket-dev" {
  bucket = "pod4-bucket-dev"
}
```
This creates an S3 bucket named `pod4-bucket-dev` for development purposes.

### Artifact Storage S3 Bucket
```hcl
resource "aws_s3_bucket" "artifact_bucket" {
  bucket = "pod4-artifact-bucket-luit"
}
```
This bucket is used to store CodePipeline artifacts.

## Public Access Configuration
```hcl
resource "aws_s3_bucket_public_access_block" "s3_bucket_public_access_block" {
  bucket = aws_s3_bucket.s3-bucket-dev.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}
```
This resource allows public access to the development S3 bucket by disabling access restrictions.

## S3 Bucket Policy for Public Read Access
```hcl
resource "aws_s3_bucket_policy" "allow_public_get_object" {
  bucket = aws_s3_bucket.s3-bucket-dev.id
  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadGetObject",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "${aws_s3_bucket.s3-bucket-dev.arn}/*"
    }
  ]
}
POLICY
}
```
This policy enables public read access (`s3:GetObject`) for objects stored in the development S3 bucket.

## Static Website Hosting Configuration
```hcl
resource "aws_s3_bucket_website_configuration" "static-website" {
  bucket = aws_s3_bucket.s3-bucket-dev.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}
```
This configures the S3 bucket to host a static website with `index.html` as the default document and `error.html` for errors.

## CloudFront Distribution
### CloudFront Origin Access Identity
```hcl
resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  comment = "Access Identity for S3 static site"
}
```
This creates an Origin Access Identity (OAI) for CloudFront to access the S3 bucket securely.

### CloudFront Distribution Setup
```hcl
resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.s3-bucket-dev.bucket_regional_domain_name
    origin_id   = aws_s3_bucket.s3-bucket-dev.id

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "S3 bucket distribution"
  default_root_object = "index.html"
  retain_on_delete    = true

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_s3_bucket.s3-bucket-dev.id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
  }

  restrictions {
    geo_restriction {
      restriction_type = "blacklist"
      locations        = ["CN", "RU"]
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
```
This configures a CloudFront distribution to serve content from the S3 bucket while restricting access from China (CN) and Russia (RU).

## AWS CodePipeline for CI/CD
This CodePipeline is configured to automatically trigger a deployment when `index.html` and `error.html` are updated in a GitHub repository using a GitHub App connection. Changes are first deployed to the `dev` branch, reviewed, and approved before merging into the `main` branch, which triggers the final deployment.

```hcl
resource "aws_codepipeline" "pipeline" {
  name     = "static-site-pipeline"
  role_arn = var.CodePipelineServiceRolearn

  artifact_store {
    location = aws_s3_bucket.artifact_bucket.id
    type     = "S3"
  }
```
### Source Stage - GitHub Trigger
```hcl
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
```
This stage pulls the `index.html` and `error.html` files from the `main` branch of a GitHub repository after they have been merged from the `dev` branch.

### Approval Stage
```hcl
  stage {
    name = "Approval"
    action {
      name     = "ManualApproval"
      category = "Approval"
      owner    = "AWS"
      provider = "Manual"
      version  = "1"
    }
  }
```
This stage requires manual approval before proceeding to deployment.

### Deployment Stage - Upload to S3
```hcl
  stage {
    name = "Deploy"
    action {
      name     = "DeployToS3"
      category = "Deploy"
      owner    = "AWS"
      provider = "S3"
      version  = "1"

      input_artifacts = ["SourceOutput"]

      configuration = {
        BucketName = aws_s3_bucket.s3-bucket-dev.bucket
        Extract    = "true"
      }
    }
  }
}
```
This stage deploys the extracted files to the development S3 bucket, making them available for the static website.
