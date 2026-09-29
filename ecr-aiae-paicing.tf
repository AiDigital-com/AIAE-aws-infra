# ECR repository for Pacing.
#
# One repository holds all FOUR images of a release, distinguished by tag
# prefix:
#   1.0.0-snapshot-<commit>          dash-gate, the API           (DEV)
#   builder-1.0.0-snapshot-<commit>  pacing-builder               (DEV)
#   fetcher-1.0.0-snapshot-<commit>  bq-fetcher                   (DEV)
#   migrate-1.0.0-snapshot-<commit>  node-pg-migrate migrations   (DEV)
# PROD drops the `-snapshot` segment, so a DEV artifact can never be mistaken
# for a released one. Tags are immutable, so re-running a workflow for an
# already built commit reuses the existing artifacts.

resource "aws_ecr_repository" "paicing" {
  count = var.enable_paicing ? 1 : 0

  name                 = local.paicing_ecr_repository_name
  image_tag_mutability = "IMMUTABLE"

  encryption_configuration {
    encryption_type = "AES256"
  }

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "paicing" {
  count = var.enable_paicing ? 1 : 0

  repository = aws_ecr_repository.paicing[0].name

  # The count is multiplied by FOUR because a Pacing release is four images.
  # Expiring them independently would leave a release that cannot migrate, or
  # an application pod whose builder sidecar image has been deleted — and the
  # rollback workflow refuses any target whose artifact set is incomplete, so a
  # too-aggressive policy here quietly destroys rollback targets.
  policy = var.environment == "dev" ? jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep the latest ${var.paicing_snapshot_image_set_retention} DEV snapshot release sets (4 images each)"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["*-snapshot-*"]
          countType      = "imageCountMoreThan"
          countNumber    = var.paicing_snapshot_image_set_retention * 4
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
