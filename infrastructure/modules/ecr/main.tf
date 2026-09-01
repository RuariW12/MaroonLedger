resource "aws_ecr_repository" "app" {
  name                 = var.project_name
  image_tag_mutability = var.image_tag_mutability
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}

# Without this the repository grows without limit. Every push from CI is a new
# tag, since images are tagged by commit SHA, so nothing is ever overwritten and
# nothing is ever reclaimed. Ten is enough to roll back several deploys.
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep the ten most recent images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = { type = "expire" }
      }
    ]
  })
}
