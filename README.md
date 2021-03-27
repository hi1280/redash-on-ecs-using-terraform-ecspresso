# Example of Redash on Amazon ECS using Terraform and ecspresso

## Requirments
- Terraform(https://www.terraform.io/downloads.html)
- ecspresso(https://github.com/kayac/ecspresso)

## Settings
Create an S3 bucket to store the tfstate.  
Configure the Terraform backend to the S3 bucket you created.  
Also, set the tfstate in the ecspresso config.yaml in the same way.

## Usage

### Create resources

```sh
$ cd terraform
$ terraform init
$ terraform apply
$ cd ecspresso
$ ecspresso run --config create_db/config.yaml --task-def create_db/ecs-task-def.json
$ ecspresso create --config worker/config.yaml
$ ecspresso create --config adhoc_worker/config.yaml
$ ecspresso create --config scheduled_worker/config.yaml
$ ecspresso create --config server/config.yaml
```

### Access Redash
Access the DNS name of the ALB with a browser.
