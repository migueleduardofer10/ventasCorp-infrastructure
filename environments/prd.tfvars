# ── Environment: prd ──────────────────────────────────────────────────

environment           = "prd"
project_name          = "delosi-ventascorp"
aws_region            = "us-east-1"
execution_environment = "Production"

# ── VPC ──────────────────────────────────────────────────────
vpc_id            = "vpc-abd6f5d0"
security_group_id = "sg-0d64facc304dc364f"
subnet_id1        = "subnet-093ec91b2f0071dfd"
subnet_id2        = "subnet-00c01d9777a1865a6"

# ── Lambda ────────────────────────────────────────────────────────────
lambda_source_path = "./lambda_code"

# ── Secrets Manager ──────────────────────────────────────────────────
db_secret_name  = "delosi-alfie-ventascorp-prd/db"
app_secret_name = "delosi-alfie-ventascorp-prd/app"
