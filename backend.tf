terraform {
  backend "s3" {
    bucket         = "nexti-tfstate"
    key            = "nextisimple/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "teste"
    encrypt        = true
  }
}
