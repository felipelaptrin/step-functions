module "resize-image" {
  source         = "./modules/resize-image"
  query_language = "jsonata"
}

module "should-i-deploy" {
  source = "./modules/should-i-deploy"
}

module "create-new-user" {
  source = "./modules/create-new-user"
  email  = var.email
}

module "bucket-replication" {
  source = "./modules/bucket-replication"
}