provider "archive" {
  version = "~> 1.3"
}

provider "aws" {
  version = "~> 2.68"
  region  = "us-east-1"
}

terraform {
  backend "remote" {
    organization = "boox"

    workspaces {
      name = "boox"
    }
  }
}
