terraform {
  backend "s3" {
    bucket       = "terraform-practice-tfstate-540444578784"
    key          = "terraform-practice/bootstrap.tfstate"
    region       = "ap-northeast-1"
    use_lockfile = true
    encrypt      = true
  }
}
