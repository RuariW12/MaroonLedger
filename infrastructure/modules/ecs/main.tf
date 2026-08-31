resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 100
  }
}

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = 30
}

resource "aws_ecs_task_definition" "app" {
  family                   = "${var.project_name}-app"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "${var.project_name}-app"
      image     = var.container_image
      essential = true

      portMappings = [
        {
          containerPort = 3000
          protocol      = "tcp"
        }
      ]

      # Non-sensitive configuration. Anything secret belongs in `secrets`
      # below, which resolves at task start and never appears in the task
      # definition, the console, or `describe-task-definition` output.
      environment = [
        { name = "AWS_REGION", value = var.region },
        { name = "AI_PROVIDER", value = var.ai_provider },
        { name = "BEDROCK_MODEL", value = var.bedrock_model },
        { name = "BEDROCK_API", value = var.bedrock_api },
        { name = "AUTH_ISSUER", value = var.auth_issuer },
        { name = "AUTH_JWKS_URL", value = var.auth_jwks_url },
        # Not a secret: the client ID is public by design and ships in the
        # frontend bundle. It is an audience check, not a credential.
        { name = "AUTH_CLIENT_ID", value = var.auth_client_id },

        # Connection coordinates are not secret; only the credentials are, and
        # those arrive through `secrets` below. The RDS-managed secret holds
        # username and password only, so these must be supplied here.
        { name = "DB_HOST", value = var.db_host },
        { name = "DB_PORT", value = tostring(var.db_port) },
        { name = "DB_NAME", value = var.db_name },
        { name = "DB_SSLMODE", value = "require" },

        # Analytics emitter. Off unless the data stack is deployed and wired
        # in, matching AI_PROVIDER's default-to-inert posture.
        { name = "DATA_PIPELINE", value = var.data_pipeline },
        { name = "DATA_PIPELINE_STREAM", value = var.data_pipeline_stream_name },
      ]

      secrets = [
        {
          name      = "DB_CREDENTIALS"
          valueFrom = var.db_credentials_secret_arn
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "app"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "app" {
  name            = "${var.project_name}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = var.private_subnet_ids
    security_groups = [var.ecs_security_group_id]
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = "${var.project_name}-app"
    container_port   = 3000
  }
}

resource "aws_iam_role" "ecs_execution" {
  name = "${var.project_name}-ecs-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_secrets" {
  name = "${var.project_name}-ecs-secrets"
  role = aws_iam_role.ecs_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = var.db_credentials_secret_arn
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = var.kms_key_arn
      }
    ]
  })
}

resource "aws_iam_role" "ecs_task" {
  name = "${var.project_name}-ecs-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

# Bedrock access belongs to the task role, not the execution role: the
# application calls Bedrock at runtime, whereas the execution role exists for
# the ECS agent to pull images and write logs before the container starts.
# Keeping them separate means application code cannot borrow the agent's
# permissions.
resource "aws_iam_role_policy" "ecs_task_bedrock" {
  count = var.ai_provider == "bedrock" ? 1 : 0

  name = "${var.project_name}-ecs-task-bedrock"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        # Scoped to Anthropic foundation models in this region rather than "*".
        # The task has no reason to invoke any other model or provider.
        # A "us." inference profile routes requests across several US regions,
        # and IAM is evaluated against the underlying foundation model in
        # whichever region serves it -- so pinning the model ARN to one region
        # fails intermittently and confusingly. The wildcard is on region only;
        # this still grants nothing beyond Anthropic models.
        Resource = [
          "arn:aws:bedrock:*::foundation-model/anthropic.*",
          "arn:aws:bedrock:${var.region}:${data.aws_caller_identity.current.account_id}:inference-profile/*",
        ]
      }
    ]
  })
}

# Firehose write access for the analytics emitter.
#
# On the task role, not the execution role -- the same split as the Bedrock
# policy above. The application calls PutRecordBatch at runtime; the execution
# role exists for the ECS agent before the container starts and has no reason
# to reach the delivery stream.
#
# Created only when the pipeline is enabled, so a compute stack deployed
# without the data stack carries no dangling permission to a stream that does
# not exist.
resource "aws_iam_role_policy" "ecs_task_firehose" {
  count = var.data_pipeline_stream_arn != "" ? 1 : 0

  name = "${var.project_name}-ecs-task-firehose"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "firehose:PutRecord",
          "firehose:PutRecordBatch",
        ]
        # This one stream. Not firehose:* and not a wildcard ARN: the task
        # writes transaction events and nothing else, so it should not be able
        # to publish into any other stream in the account.
        Resource = [var.data_pipeline_stream_arn]
      }
    ]
  })
}
