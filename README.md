## The Minimal Mixologist

This is the website for The Minimal Mixologist ([www.theminimalmixologist.com](https://www.theminimalmixologist.com/)).

### Dependencies

* Terraform (or [OpenTofu](https://opentofu.org/)) for managing infrastructure
* Python with [Poetry](https://python-poetry.org/) for uploading files to S3
* [Zola](https://www.getzola.org/) for building the website

### Running locally

The website is built and deployed on every push to `main`. To build it locally:

```
$ cd website
$ zola build # or `zola serve` for development
```

To deploy from your own machine, your AWS credentials must be accessible. The easiest way to get started is to make sure your access key ID and secret keys are exported as [environment variables](https://docs.aws.amazon.com/cli/v1/userguide/cli-configure-envvars.html) in your shell. See [the AWS docs](https://docs.aws.amazon.com/cli/v1/userguide/cli-chap-authentication.html) for more information.

To apply the Terraform infrastructure configuration:

```
$ cd infrastructure
$ terraform apply
```

To upload the built website to S3 and invalidate the CloudFront cache, create a Python 3 virtual environment with Poetry and run `upload.py`:

```
$ poetry install
$ poetry run ./upload.py
```
