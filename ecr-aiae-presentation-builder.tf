# ECR repository for the AIAE Presentation Builder.
#
# One repository holds both images of a release, distinguished by tag prefix:
#   1.0.0-snapshot-<commit>            application (DEV)
#   liquibase-1.0.0-snapshot-<commit>  Liquibase migrations (DEV)
# Tags are immutable, so re-running a workflow for an already built commit
# reuses the existing artifact instead of silently republishing a new image
# under a tag that other environments may already be running.

resource "aws_ecr_repository" "presentation_builder" {
  count = var.enable_presentation_builder ? 1 : 0

  name                 = local.presentation_builder_ecr_repository_name
  image_tag_mutability = "IMMUTABLE"

  encryption_configuration {
    encryption_type = "AES256"
  }

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "presentation_builder" {
  count = var.enable_presentation_builder ? 1 : 0

  repository = aws_ecr_repository.presentation_builder[0].name

  # DEV keeps a bounded number of snapshot pairs. The count is doubled because
  # every release is an application image AND its paired Liquibase image;
  # expiring them independently would leave a deployment that cannot migrate.
  policy = var.environment == "dev" ? jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep the latest ${var.dev_snapshot_image_pair_retention} DEV application and Liquibase snapshot pairs"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["*-snapshot-*"]
          countType      = "imageCountMoreThan"
          countNumber    = var.dev_snapshot_image_pair_retention * 2
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Delete untagged DEV images after one day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = {
          type = "expire"
        }
      },
    ]
    }) : jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Delete untagged PROD images after seven days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type = "expire"
        }
      },
    ]
  })
}
