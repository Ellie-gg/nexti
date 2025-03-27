provider "aws" {
  region = var.aws_region
  default_tags {
    tags = var.common_tags
  }
}

provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"
}
