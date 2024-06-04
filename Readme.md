# Automation-Oriented Email with SES, StepFunctions and EventBridge #

This repository implements robust, low-cost and compliance-oriented email service based on AWS Simple Email Service (SES) and intended for use cases centered on email-based automation (from auto reply to workflow integration). This solution is especially useful for those maintaining multiple domains in a global context, who require email service aligned with priviacy requirements, and who are comfortable getting flexible automation without a graphical user interface.

For each configured domain, MX records are added with latency-based routing to ensure clients may use the geographically "local" regional endpoint, with the email content remaining "in region" and a global DynamoDB table with replication to store "mailbox" metadata (no PII). SPF, DKIM and DMARC are also configured for each domain to support reliable email delivery. This robust infrastructure ensures that email communication remains functional even in the face of an entire AWS region going down or large-scale internet outages (e.g. a broken undersea cable).

Received/inbound email generates EventBridge events that may be used to trigger a wide varierty of automated processes. 

# Features

This is a work in progress serverless system for receiving email, and it already has some pretty subsstantial advantages (and obvious disadvantages) over typical "self hosted" setups. Here is what you get:

- Very inexpensive (essentially free for low email volumes).
- Emails arriving at your domains are handled in the "closest" region you've configured, parsed and the attachments and embedded parts (images) extracted to your region's S3 bucket.  
- The location of the message is added to the DDB table along with the date, so there is only one place to look for a record of what emails arrived in each region. 
- The S3 URIs to the message objects and other metadata (subject, sender, to, cc, subject, etc.) are combined into a JSON object which is saved alongside the contents in S3, as well as broadcast to EventBridge for handling in downstream processes.
- Multi-region deployment and latency-based routing in Route53 ensure industrial-strength availability.
- Optionally, the region-specific domain name list allows you to control where emails are stored (e.g. keeping all email to your .uk domain in Ireland and your .com domain in the US).

Speaking of spam, for kicks this repository can use the OpenAI API to summarize the email body. To use this feature you'll need to set up an OpenAI account and add an AWS SecretsManager secret called "OPENAPI" with a key "API_TOKEN" and the value being your API token (make sure to use the replication feature to easily make it available in the three regions).  If you don't want to use this feature, just put a placeholder in for the token and it'll work just fine.

# Caveats

You don't get a UI or any kind of client, so instead of using `rmail` you're going to be automatically processing email or using `aws dynamodb query ... | aws s3api ...` commands to read that spam.

Also please note that while the resources created by this repository are very inexpensive, they are not free, and in certain circumstances can become expensive. Please be aware of the pricing and take it into consideration.

This solution may not align with your concept of a production-quality stack, as it's a work in progress. It doesn't have managed encryption, relies on AWS for spam protection (which you are responsible for paying for), and doesn't include logging or monitoring, among other things.

Use this solution at your own risk.

# Prerequisities and Deployment (CLI and CodeBuild)
- ### ForEach Macro
Before deploying this solution, you'll need to install the [ForEach cloudformation macro](https://github.com/mlhpdx/cloudformation-macros) in your AWS account. Using this macro makes customizing the list of domains much easier and is worth the effort.

- ### .Net 8 SDK
This repository includes a Lambda function using the .Net 8 managed runtime. You'll need to have the .Net 8 SDK installed wherever you're building it (locally and/or in CodeBuild).

- ### Decide which Regions to Deploy
This service may deploy to any combination of the [AWS regions that support SES email receiving](https://docs.aws.amazon.com/ses/latest/dg/regions.html#region-receive-email) (the default is `us-west-2`, `us-east-1`, and `eu-west-1`). SES email receiving is not available in all regions, so you'll need to choose from the available regions. The resources created by this solution are inexpensive but please be aware of the pricing and take it into consideration.

Set the environment variable `DEPLOY_TO_REGIONS` to a space-separated list of regions you want to deploy to (either in your CLI or CodeBuild).

```bash
> export DEPLOY_TO_REGIONS="us-west-2 us-east-1 ca-central-1 ap-northeast-1 eu-west-1"
```

- ### Registered Domain Names in SSM
You must have control of the domain names you want to use with this service, and have DNS service for them provided by AWS Route53.

The domain names to enabled with email receiving are defined in a ParameterStore value called `/config/prod/email-delivery/DOMAIN_NAMES`. Add your list of domains to that value *in each region* as a comma-separated (no spaces) list. The lists can be the same or different in each region.

```bash
> export DOMAIN_NAMES=foo.com,bar.com,baz.com

> for REGION in us-west-2 us-east-1 eu-west-1; do aws ssm put-parameter --name "/config/prod/email-delivery/DOMAIN_NAMES" --value $DOMAIN_NAMES --type String --region $REGION; done  
```

- ### Hosted Zones
Before the deployment, you'll need hosted zones in Route 53 for the domain names you're using. Create them if you don't already have them. Default, empty zones are fine.

```bash
> for DOMAIN in $(echo $DOMAIN_NAMES | tr "," " "); do aws route53 create-hosted-zone --name $DOMAIN --caller-reference "create for email delivery"; done
```

- ### Buckets for Deployment in Each Region
Using AWS SAM means having a bucket to hold the built artifacts before they can be sent to CloudFormation.  You probably have such a bucket, but you may not have one in each region following a prefix/region naming pattern.

```bash
> export BUCKET_NAME_PREFIX=my-build-bucket-name

> for REGION in $DEPLOY_TO_REGIONS; do aws s3 create-bucket --bucket $BUCKET_NAME_PREFIX-$REGION --region $REGION; done
```

- ### API Gateway CloudWatch Logs Role ARN is Set
See: https://www.chrisarmstrong.dev/posts/setting-up-api-gateway-cloudwatch-logging-for-your-aws-account

## CodeBuild (optional)
This repository contains structured (nested) AWS SAM templates and includes buildspecs to use with CodeBuild. If you want to use this method of ci/cd, you'll need to set up a CodeBuild project in region `us-west-2` configured for "batch" builds and point it to this repo (or your own fork). The service role for that CodeBuild project will need permissions for IAM, DDB, Step Functions, Route53, S3, and probably more. 

If you wish to support regions other than the default, set the environment variable `DEPLOY_TO_REGIONS` on the code build project to a space-separated list of regions (e.g. `us-west-2 us-east-1 eu-west-1 eu-west-2`).

## Deployment Scripts
You can also deploy this solution from the command line if you have the AWS CLI version 2 installed and appropriate credentials configured. The scripts folder contains everything you need, and is probably easier than CodeBuild if you're just "having a look". 

To run the scripts locally you'll need to:

- Install `cfn-lint` (e.g. `pip install cfn-lint`).
- Set the `BUCKET_NAME_PREFIX` environment variable to the prefix of the name of the buckets you want to use for the deployment artifacts (the region will be added automatically as a suffix).
- Set the `BUCKET_KEY_PREFIX` environment variable to the prefix of the key you want to use for the deployment artifacts (a suffix will be appended of the artifacts created for each deploy by `sam deploy`).
- If not already set, set the `DOMAIN_NAMES` environment variable to your comma-separated (no spaces) list of domain names.
- Optionally, set the `DEPLOY_TO_REGIONS` environment variable to a space-separated list of regions you want to deploy to (e.g. `us-west-2 us-east-1 eu-west-1`).

Note that the scripts assume that they'll be run from the repository root:

```bash
> ./scripts/checks.sh && ./scripts/deploy-global.sh && ./scripts/deploy-region.sh
```

Once you run the scripts, the global resources will be created in a stack called email-delivery-global, and a stack called `email-delivery` will be ready in `us-west-1`, `us-east-2` and `eu-west-1`.

## Activate SES Rule Sets

After the first deployment is finished you'll need to go to each SES region and manually activate the rule sets under "Email Receiving" in the SES Console. You only need to do this once when initially setting-up the stacks (not with each subsequent deployment).  As far as I know this can't be done via CloudFormation.

# License
This code is available under the MIT license. If you find it helpful, please consider sending me a note or giving me credit. Enjoy!
