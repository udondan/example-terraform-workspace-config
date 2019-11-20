locals {
  configs = {

    _defaults = {
      ec2_instance_type = "t2.nano"
      regions           = ["us-east-1"]
    }

    dev = {} // use config from _defaults ^

    staging = {
      ec2_instance_type = "t2.medium"
      regions = [
        "us-east-1",
        "eu-central-1",
      ]
    }

    production = {
      ec2_instance_type = "t2.xlarge"
      regions = [
        "us-east-1",
        "us-west-2",
        "eu-central-1",
        "ap-east-1",
      ]
    }

  }

  config = merge(
    lookup(local.configs, "_defaults"),
    lookup(local.configs, terraform.workspace)
  )
}
