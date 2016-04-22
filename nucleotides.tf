provider "aws" {
    access_key = "${var.access_key}"
    secret_key = "${var.secret_key}"
    region     = "us-west-1"
}

resource "aws_instance" "evaluation" {
	ami           = "ami-a8d9a6c8"
	instance_type = "t2.micro"

	connection {
		user     = "ubuntu"
		key_file = "${var.key_path}"
	}

	key_name = "${var.key_name}"
	security_groups = ["nucleotides-evaluation"]
}
