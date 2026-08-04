terraform {
  backend "s3" {
    bucket       = "terraform-practice-tfstate-540444578784"
    key          = "terraform-practice/terraform.tfstate"
    region       = "ap-northeast-1"
    use_lockfile = true
    encrypt      = true
  }
}
