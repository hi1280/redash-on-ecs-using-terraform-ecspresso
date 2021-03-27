# rds
resource "random_string" "pg_password" {
  length  = 32
  special = false
}

resource "aws_db_instance" "pg" {
  allocated_storage         = 50
  backup_retention_period   = 7
  backup_window             = "00:05-00:35"
  db_subnet_group_name      = aws_db_subnet_group.pg.name
  engine                    = "postgres"
  engine_version            = "13.1"
  final_snapshot_identifier = "redash-final"
  identifier                = "redash"
  instance_class            = "db.t3.micro"
  maintenance_window        = "sun:20:00-sun:20:30"
  parameter_group_name      = aws_db_parameter_group.pg.name
  port                      = 5432
  storage_type              = "gp2"
  storage_encrypted         = true
  username                  = "root"
  password                  = random_string.pg_password.result
  vpc_security_group_ids    = [aws_security_group.pg.id]
  lifecycle {
    ignore_changes = [engine_version]
  }
}

resource "aws_db_subnet_group" "pg" {
  name       = "redash"
  subnet_ids = module.vpc.public_subnets
}

resource "aws_db_parameter_group" "pg" {
  name   = "redash"
  family = "postgres13"

  parameter {
    name  = "log_statement"
    value = "all"
  }
  parameter {
    name  = "log_min_duration_statement"
    value = 3000
  }
}

resource "aws_security_group" "pg" {
  name        = "redash-postgres"
  description = "Security group for Redash database"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "Allow postgres inbound traffic from Redash"
    from_port       = "5432"
    protocol        = "tcp"
    security_groups = [aws_security_group.redash.id]
    to_port         = "5432"
  }

}

# elasticache
resource "aws_elasticache_replication_group" "redis" {
  replication_group_id          = "redash"
  replication_group_description = "Redis for Redash"
  number_cache_clusters         = 1
  node_type                     = "cache.t3.micro"
  auto_minor_version_upgrade    = true
  engine                        = "redis"
  engine_version                = "6.x"
  parameter_group_name          = aws_elasticache_parameter_group.redis.name
  port                          = 6379
  subnet_group_name             = aws_elasticache_subnet_group.redis.name
  security_group_ids            = [aws_security_group.redis.id]
  maintenance_window            = "mon:20:00-mon:21:00"
  lifecycle {
    ignore_changes = [engine_version]
  }
}

resource "aws_elasticache_subnet_group" "redis" {
  name        = "redash"
  description = "Subnet group of Redis for Redash"
  subnet_ids  = module.vpc.public_subnets
}

resource "aws_elasticache_parameter_group" "redis" {
  name        = "redash"
  family      = "redis6.x"
  description = "Customized redis parameter group for Redash"

  parameter {
    name  = "timeout"
    value = "3600"
  }
}

resource "aws_security_group" "redis" {
  name        = "redash-redis"
  description = "Security group of Redis for Redash"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "Allow redis inbound traffic from Redash"
    from_port       = "6379"
    protocol        = "tcp"
    security_groups = [aws_security_group.redash.id]
    to_port         = "6379"
  }
}


# ecs
resource "aws_ecs_cluster" "redash" {
  name = "redash"
}

resource "aws_security_group" "redash" {
  name        = "redash-ecs"
  description = "Security group for Redash"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "Allow http inbound traffic from load balancer"
    from_port       = "5000"
    protocol        = "tcp"
    security_groups = [aws_security_group.lb_redash.id]
    to_port         = "5000"
  }

  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = "0"
    protocol    = "-1"
    to_port     = "0"
  }
}

# alb
resource "aws_lb" "redash" {
  name               = "redash"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb_redash.id]
  subnets            = module.vpc.public_subnets
  ip_address_type    = "ipv4"
}

resource "aws_security_group" "lb_redash" {
  name        = "redash-load-balancer"
  description = "Security group of LB for Redash"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Allow https inbound traffic from load balancer"
    from_port   = "443"
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    to_port     = "443"
  }

  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = "0"
    protocol    = "-1"
    to_port     = "0"
  }

}

resource "aws_lb_listener" "redash" {
  load_balancer_arn = aws_lb.redash.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.redash.arn
  default_action {
    target_group_arn = aws_lb_target_group.redash.arn
    type             = "forward"
  }
}

resource "aws_lb_target_group" "redash" {
  name                 = "redash"
  port                 = 5000
  protocol             = "HTTP"
  vpc_id               = module.vpc.vpc_id
  deregistration_delay = 30
  slow_start           = 0
  target_type          = "ip"

  health_check {
    interval            = 30
    path                = "/login"
    protocol            = "HTTP"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    matcher             = "200,302"
  }
}

# acm
resource "aws_acm_certificate" "redash" {
  domain_name       = "*.hi1280.com"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# cloudwatch
resource "aws_cloudwatch_log_group" "redash" {
  name              = "/ecs/redash"
  retention_in_days = 14
}

# iam
resource "aws_iam_role" "redash" {
  name               = "redash"
  assume_role_policy = data.aws_iam_policy_document.task_assume_role.json
}

data "aws_iam_policy_document" "task_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "redash" {
  role       = aws_iam_role.redash.id
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "redash_ssm" {
  name   = "redash-ssm"
  policy = data.aws_iam_policy_document.redash_ssm.json
  role   = aws_iam_role.redash.id
}

data "aws_iam_policy_document" "redash_ssm" {
  statement {
    actions   = ["ssm:GetParameters"]
    resources = ["arn:aws:ssm:ap-northeast-1:${data.aws_caller_identity.current.account_id}:parameter/redash/*"]
  }
}

# ssm
resource "random_string" "cookie_secret" {
  length  = 32
  special = false
}

resource "aws_ssm_parameter" "cookie_secret" {
  name  = "/redash/cookie_secret"
  type  = "SecureString"
  value = random_string.cookie_secret.result
}

resource "random_string" "secret" {
  length  = 32
  special = false
}

resource "aws_ssm_parameter" "secret" {
  name  = "/redash/secret"
  type  = "SecureString"
  value = random_string.secret.result
}

resource "aws_ssm_parameter" "redash_db_url" {
  name  = "/redash/db_url"
  type  = "SecureString"
  value = "postgresql://${aws_db_instance.pg.username}:${aws_db_instance.pg.password}@${aws_db_instance.pg.address}/postgres"
}

resource "aws_ssm_parameter" "redash_redis_url" {
  name  = "/redash/redis_url"
  type  = "String"
  value = "redis://${aws_elasticache_replication_group.redis.primary_endpoint_address}"
}