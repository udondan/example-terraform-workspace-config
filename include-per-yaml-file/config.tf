data "local_file" "_defaults" {
  filename = "${path.module}/config/_defaults.yml"
}

data "local_file" "config" {
  filename = "${path.module}/config/${terraform.workspace}.yml"
}

locals {
  config = merge(
    yamldecode(data.local_file._defaults.content),
    yamldecode(data.local_file.config.content)
  )
}
