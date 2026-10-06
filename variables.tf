variable "company" {
  description = "Nombre de la compañía o proyecto"
  type        = string
  default     = "Delosi"
}

variable "project" {
  description = "Nombre del proyecto"
  type        = string
  default     = "ventasCorp"
}

variable "project_name" {
  description = "Project name for resource tagging"
  type        = string
  default     = "delosi-ventascorp"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Entorno (dev, stg, prd)"
  type        = string
  validation {
    condition     = contains(["dev", "stg", "prd"], var.environment)
    error_message = "El entorno debe ser 'dev', 'stg' o 'prd'."
  }
}

# ── VPC ───────────────────────────────────────────────────────────────

variable "vpc_id" {
  description = "VPC ID for Lambda functions"
  type        = string
}

variable "security_group_id" {
  description = "Security group ID for Lambda functions"
  type        = string
}

variable "subnet_id1" {
  description = "First private subnet ID (SUBPRIVZA002)"
  type        = string
}

variable "subnet_id2" {
  description = "Second private subnet ID (SUBPRIVZC002)"
  type        = string
}

# ── Lambda ────────────────────────────────────────────────────────────

variable "lambda_source_path" {
  description = "Path to Lambda function source code"
  type        = string
  default     = "./lambda_code"
}

variable "execution_environment" {
  description = "Execution environment for the Lambda function"
  type        = string
  default     = "Development"
}

# ── Secrets Manager (managed manually) ──────────────────────────────

variable "db_secret_name" {
  description = "Secreto con la conexión a la base de datos, compartido por todas las lambdas"
  type        = string
}

variable "app_secret_name" {
  description = "Secreto con la configuración sensible (JwtAuth, SAP, etc.), compartido por todas las lambdas"
  type        = string
}

# ── API Gateway ──────────────────────────────────────────────────────

variable "allow_origin" {
  description = "Origen permitido en CORS del API Gateway. Lo consume el frontend de Ventas Corp; ajustar al dominio real por ambiente. Sin comillas: la receta las agrega"
  type        = string
  default     = "*"
}
