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

resource "aws_db_instance" "default" {
	identifier              = "nucleotides-staging-db"
	allocated_storage       = 5
	engine                  = "postgres"
	engine_version          = "9.4.5"
	instance_class          = "db.t1.micro"
	multi_az                = false
	backup_retention_period = 0
	publicly_accessible     = true
	storage_encrypted       = false
	storage_type            = "standard"

	name     = "nucleotides"
	password = "nucleotides"
	username = "nucleotides"
	port     = 5433
}
