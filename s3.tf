# ── Buckets S3 de Ventas Corp ───────────────────────────────────────────────
#
# Un bucket con la receta modules/s3. La receta arma el nombre como
# {company}-{project}-{bucket_name}-{env} en minúsculas, por eso bucket_name
# lleva el sufijo "-s3": así sale delosi-ventascorp-vales-s3-{env}, el nombre
# que propuso DevOps.
#
# Lo usa document-generation para guardar los PDF y PNG de los vales
# (prefijo pdf/[ruc]/[factura]). El permiso está en lambdas.tf.

module "documents_bucket" {
  source      = "git::https://gitlab.com/delosi/devops/iac-templates//modules/s3?ref=main"
  company     = var.company
  project     = var.project
  environment = var.environment
  bucket_name = "vales-s3"
  tags        = local.common_tags
}
