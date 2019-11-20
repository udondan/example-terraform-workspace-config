The suggested best practices for organizing configuration for multiple workspaces/environments is to call Terraform with `-var-file=$env` to include a specific tfvars file.

Of course this works. But it seems to be error prone if you allow to trigger an apply against any workspace with just any configuration:

```bash
terraform workspace select production
terraform apply -var-file=config/staging.tfvars
```

Furthermore this cannot be used in Terraform Cloud, where you have to specify workspace related vars in the workspace configuration itself:

![Terraform Cloud Variable configuration](https://thepracticaldev.s3.amazonaws.com/i/s1trk20rgji6tfgyldv5.png)

There is no option for including tfvars per workspace.

### Select config automatically based on the workspace

Unfortunately there is no functionality to [automatically include a tfvars file based on the workspace name](https://github.com/hashicorp/terraform/issues/15966) nor is there support for [conditionally including tfvars files](https://github.com/hashicorp/terraform/issues/1478).

So you got to build something yourself. You can access the current workspace name via `terraform.workspace`. There are a couple of things you can do with this value.

Below are 3 solutions which all have the same exact outcome. The defined config is stored in `local.config` and can be access via `local.config.ec2_instance_type` etc.

All 3 solutions support default values, so you're not required to define every config option in every environment.

All examples are available in [this repository](https://github.com/udondan/example-terraform-workspace-config).

### 1. Inline expressions to select correct config from a map

```hcl
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
```

**Pros:**

- Straight forward

**Cons:**

- Cannot split config into separate files. Therefore could quickly get hard to maintain and compare environment config.

### 2. Load config from YAML files

[Directory structure:](https://github.com/udondan/example-terraform-workspace-config/tree/master/include-per-yaml-file)

```tree
.
├── config
│   ├── _defaults.yml
│   ├── dev.yml
│   ├── production.yml
│   └── staging.yml
├── config.tf
├── main.tf
```

Example content of [`config/production.yml`](https://github.com/udondan/example-terraform-workspace-config/blob/master/include-per-yaml-file/config/production.yml):

```yaml
---
ec2_instance_type: t2.xlarge

regions:
  - us-east-1
  - us-west-2
  - eu-central-1
  - ap-east-1
```

The config is loaded in [`config.yml`](https://github.com/udondan/example-terraform-workspace-config/blob/master/include-per-yaml-file/config.tf):

```hcl
data "local_file" "defaults" {
  filename = "${path.module}/config/_defaults.yml"
}

data "local_file" "config" {
  filename = "${path.module}/config/${terraform.workspace}.yml"
}

locals {
  config = merge(
    yamldecode(data.local_file.defaults.content),
    yamldecode(data.local_file.config.content)
  )
}
```

**Pros:**

- Straight forward
- Config for every environment resides in its own file

**Cons:**

- No HCL expressions are possible in the config itself

### 3. Create a module per environment and return the config as an output

[Directory structure:](https://github.com/udondan/example-terraform-workspace-config/tree/master/include-per-module)

```tree
.
├── config
│   ├── _defaults
│   │   └── outputs.tf
│   ├── dev
│   │   └── outputs.tf
│   ├── main.tf
│   ├── production
│   │   └── outputs.tf
│   └── staging
│       └── outputs.tf
├── main.tf
```

In every `config/$env/outputs.tf` a single output is defined like this:

[`config/_defaults/outputs.tf`](https://github.com/udondan/example-terraform-workspace-config/blob/master/include-per-module/config/_defaults/outputs.tf):

```hcl
output "data" {
  value = {
    ec2_instance_type = "t2.nano"
    regions = [
      "us-east-1",
    ]
  }
}
```

[config/dev/outputs.tf](https://github.com/udondan/example-terraform-workspace-config/blob/master/include-per-module/config/dev/outputs.tf):

```hcl
output "data" {
  value = {} // use config from _defaults
}
```

[config/staging/outputs.tf](https://github.com/udondan/example-terraform-workspace-config/blob/master/include-per-module/config/staging/outputs.tf):

```hcl
output "data" {
  value = {
    ec2_instance_type = "t2.medium"
    regions = [
      "us-east-1",
      "eu-central-1",
    ]
  }
}

```

[config/production/outputs.tf](https://github.com/udondan/example-terraform-workspace-config/blob/master/include-per-module/config/production/outputs.tf):

```hcl
output "data" {
  value = {
    ec2_instance_type = "t2.xlarge"
    regions = [
      "us-east-1",
      "us-west-2",
      "eu-central-1",
      "ap-east-1",
    ]
  }
}
```

Since you cannot use variables in a module `source` parameter all 4 modules have to be defined in every environment. Furthermore you cannot directly access a module by name when the name is not hardcoded, so you need to additionally create a mapping like so:

[config/main.tf](https://github.com/udondan/example-terraform-workspace-config/blob/master/include-per-module/config/main.tf):

```hcl
module "_defaults" {
  source = "./_defaults"
}

module "dev" {
  source = "./dev"
}

module "staging" {
  source = "./staging"
}

module "production" {
  source = "./production"
}

locals {
  data_map = {
    dev        = module.dev.data,
    staging    = module.staging.data,
    production = module.production.data,
  }
}

output "data" {
  value = merge(
    module._defaults.data,
    lookup(local.data_map, terraform.workspace)
  )
}
```

In the [`main.tf`](https://github.com/udondan/example-terraform-workspace-config/blob/master/include-per-module/main.tf) then the module needs to be loaded and for convenience the output gets registered as a local value:

```hcl
module "config" {
  source = "./config"
}

locals {
  config = module.config.data
}
```

**Pros:**

- Config for every environment resides in its own file

**Cons:**

- Complex setup

## Conclusion

Using modules as config provider seems to be the best solution, as you can split the configuration into separate files which supports HCL expressions. The setup though is complex and requires some additional boilerplate code for every additional environment.

If you have no need for HCL expressions, the YAML solution seems to be nice as it is easy to setup and IMHO is very readable to humans.
