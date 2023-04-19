resource "aws_db_subnet_group" "education" {
  count = var.create_rds ? 1 : 0

  name       = "education"
  subnet_ids = module.vpc.private_subnets

  tags = {
    Name      = "education"
    Terraform = "true"
  }
}

resource "aws_security_group" "db_instance" {
  count = var.create_rds ? 1 : 0

  name   = "education"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [module.vpc.vpc_cidr_block]
  }

  egress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [module.vpc.vpc_cidr_block]
  }

  tags = {
    Name      = "education"
    Terraform = "true"
  }
}

resource "aws_db_instance" "education" {
  count = var.create_rds ? 1 : 0

  identifier           = "education"
  instance_class       = "db.t3.micro"
  allocated_storage    = 5
  engine               = "postgres"
  engine_version       = "14.6"
  username             = "postgres"
  password             = var.db_password
  db_subnet_group_name = aws_db_subnet_group.education[0].name
  parameter_group_name = aws_db_parameter_group.education[0].name
  publicly_accessible  = false
  skip_final_snapshot  = true
  apply_immediately    = true

  vpc_security_group_ids = [
    aws_security_group.db_instance[0].id
  ]

  tags = {
    Name      = "education"
    Terraform = "true"
  }
}

resource "aws_db_parameter_group" "education" {
  count = var.create_rds ? 1 : 0

  name   = "education"
  family = "postgres14"

  parameter {
    name  = "log_connections"
    value = "1"
  }

  tags = {
    Name      = "education"
    Terraform = "true"
  }
}
