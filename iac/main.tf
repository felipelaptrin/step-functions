module "resize-image" {
  source         = "./modules/resize-image"
  query_language = "jsonpath"
}

module "should-i-deploy" {
  source = "./modules/should-i-deploy"
}

module "create-new-user" {
  source = "./modules/create-new-user"
  email  = "" # Add your email here
}

module "bucket-replication" {
  source = "./modules/bucket-replication"
}