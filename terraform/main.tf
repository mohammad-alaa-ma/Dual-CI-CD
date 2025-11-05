provider "aws" {
  region = "us-east-1"
}

resource "aws_instance" "test_instance" {
  ami           = "ami-0ecb62995f68bb549"  
  instance_type = "t2.micro"

  tags = {
    Name = "Jenkins-Terraform-Test"
  }
}

resource "aws_instance" "test_instance2" {
  ami           = "ami-0ecb62995f68bb549"
  instance_type = "t2.micro"

  tags = {
    Name = "Jenkins-Terraform-Test-2"
  }
}
