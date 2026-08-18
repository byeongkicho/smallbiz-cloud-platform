# ──────────────────────────────────────
# RDS Subnet Group
# ──────────────────────────────────────
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "${var.project_name}-db-subnet"
  }
}

# ──────────────────────────────────────
# RDS Security Group
# ──────────────────────────────────────
resource "aws_security_group" "rds" {
  name_prefix = "${var.project_name}-rds-"
  vpc_id      = var.vpc_id

  # 규칙뿐 아니라 보안 그룹 자체에도 설명이 필요하다 (checkov CKV_AWS_23).
  # SG 목록만 봤을 때 무엇을 위한 것인지 읽히게 하는 것이 목적이다.
  description = "RDS MySQL — VPC 내부에서 3306만 수신"

  # Allow MySQL/Aurora from VPC only
  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "MySQL from VPC"
  }

  # RDS는 아웃바운드로 먼저 연결을 여는 일이 없다. 0.0.0.0/0 이그레스는
  # 관행적으로 붙던 것이고, 실제로 필요하지 않아 VPC 내부로 좁혔다.
  # (checkov CKV_AWS_382)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
    description = "VPC 내부로만 허용 — RDS는 외부로 연결을 열지 않는다"
  }

  tags = {
    Name = "${var.project_name}-rds-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ──────────────────────────────────────
# RDS Instance (MySQL 8.0)
# ──────────────────────────────────────
resource "aws_db_instance" "main" {
  # 아래 skip은 전부 "PoC 운영 패턴과 충돌하거나 상시 과금이 붙는 것"이다.
  # 판단 근거는 docs/security-baseline.md에 항목별로 적었다.
  #checkov:skip=CKV_AWS_293:deletion_protection은 destroy를 막는다 — 이 저장소는 apply/destroy 반복이 전제
  #checkov:skip=CKV_AWS_157:Multi-AZ는 월 $19 → $38. 단일 AZ는 RTO를 감수한 의도적 선택(cost-analysis.md)
  #checkov:skip=CKV_AWS_129:RDS 로그 CloudWatch 수집은 상시 과금. PoC 사이클에서 가치 대비 비용이 크다
  #checkov:skip=CKV_AWS_118:enhanced monitoring도 동일 — 분당 지표 수집에 별도 과금
  identifier = "${var.project_name}-db"

  engine         = "mysql"
  engine_version = "8.0"
  instance_class = var.db_instance_class

  allocated_storage     = 20
  max_allocated_storage = 50
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  multi_az            = false # dev 환경 — prod에서는 true
  publicly_accessible = false
  skip_final_snapshot = true # dev 환경 — prod에서는 false + final_snapshot_identifier

  # 비용이 0이면서 지적이 타당한 것들은 그냥 고쳤다 (checkov)
  iam_database_authentication_enabled = true # CKV_AWS_161 — 비밀번호 외 IAM 인증 경로 확보
  auto_minor_version_upgrade          = true # CKV_AWS_226 — 마이너 보안 패치 자동 적용
  copy_tags_to_snapshot               = true # CKV2_AWS_60 — 스냅샷에 태그 승계(비용 추적)

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  tags = {
    Name = "${var.project_name}-db"
  }
}
