# ── Buckets S3 de Ventas Corp ───────────────────────────────────────────────
#
# Dos buckets con la receta modules/s3. La receta arma el nombre como
# {company}-{project}-{bucket_name}-{env} en minúsculas, por eso bucket_name
# lleva el sufijo "-s3": así sale delosi-ventascorp-vales-s3-{env}, el nombre
# que propuso DevOps.
#
# Quién los usa:
#   vales-s3   → document-generation escribe los PDF (prefijo pdf/[ruc]/[factura])
#   models-s3  → voucher-models lee y escribe las imágenes de fondo de los modelos;
#                document-generation solo las lee (prefijo voucher-model/background-images)
#
# Los permisos de cada lambda están en lambdas.tf.

module "documents_bucket" {
  source      = "git::https://gitlab.com/delosi/devops/iac-templates//modules/s3?ref=main"
  company     = var.company
  project     = var.project
  environment = var.environment
  bucket_name = "vales-s3"
  tags        = local.common_tags
}

module "models_bucket" {
  source      = "git::https://gitlab.com/delosi/devops/iac-templates//modules/s3?ref=main"
  company     = var.company
  project     = var.project
  environment = var.environment
  bucket_name = "models-s3"
  tags        = local.common_tags
}
