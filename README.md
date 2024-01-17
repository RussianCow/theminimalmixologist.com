## The Minimal Mixologist

This is the website for The Minimal Mixologist ([www.theminimalmixologist.com](https://www.theminimalmixologist.com/)).

### Dependencies

* Terraform (or [OpenTofu](https://opentofu.org/)) for managing infrastructure
* Python with [Poetry](https://python-poetry.org/) for uploading files to S3
* [Zola](https://www.getzola.org/) for building the website

### Running

To build the website:

```
$ cd website
$ zola build # or `zola serve` for local development
```

Copy `infrastructure/sample.tfvars` into `infrastructure/prod.tfvars` and update the AWS access keys with those of your user. From there, you can run normal Terraform commands to spin up the infrastructure:

```
$ cd infrastructure
$ terraform init
$ terraform apply -var-file=prod.tfvars
```

Create a Python 3 virtual environment with Poetry, and use that to upload the files to S3 and invalidate the CloudFront cache:

```
$ poetry install
$ poetry shell
$ ./upload.py
```
