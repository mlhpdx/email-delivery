# Receiving Email with SES, StepFunctions and EventBridge #

This repository implements a low-cost email service for inbound email communication that utilizes AWS Simple Email Service (SES) and generates EventBridge events for triggering automated workflows. This solution is especially useful for those maintaining multiple domains that require email service and who are comfortable getting flexible automation without a graphical user interface.

The CodeBuild scripts in this repository deploy to the three AWS regions that support SES email receiving: `us-west-2`, `us-east-1`, and `eu-east-1`. Route53 latency-based routing is configured to ensure that clients make use of geographically "local" services (and email content remains "in region"), and a global DynamoDB table with replication is used to store "mailbox" metadata. This robust infrastructure ensures that email communication remains unaffected even if an entire AWS region goes down.

# Prerequisities and Deployment
## ForEach Macro
Before deploying this solution, you'll need to install the [ForEach cloudformation macro](https://github.com/mlhpdx/cloudformation-macros) in your AWS account. Using this macro makes customizing the list of domains much easier and is worth the effort.

## .Net 6 SDK
This repository includes a Lambda function running on .Net. You'll need to have the .Net 6 SDK installed wherever you're building it.

## Domain Names
The domain names to enabled with email receiving are defined in a ParameterStore value called `/config/prod/email-delivery/DOMAIN_NAMES`. To use your own list of domains, add that value in all three regions as a comma-separated list. The lists can be the same or different in each region.

```bash
> export DOMAIN_NAMES=foo.com,bar.com,baz.com
> for REGION in us-west-2 us-east-1 eu-west-1; do aws ssm put-parameter --name "/config/prod/email-delivery/DOMAIN_NAMES" --value $DOMAIN_NAMES --type String --region $REGION; done  
```

## Hosted Zones
Before the deployment, you'll need hosted zones in Route 53 for the domain names you're using. Create them if you don't already have them. Default, empty zones are fine.

```bash
> for DOMAIN in $(echo $DOMAIN_NAMES | tr "," " "); do aws ssm create-hosted-zone --name $DOMAIN --caller-reference "create for email delivery"; done
```

## Bucket for Deployment
Using AWS SAM means having a bucket to hold the built artifacts before they can be sent to CloudFormation.  You probably have such a bucket, but you may not have one in each region following a prefix/region naming pattern.

```bash
> export BUCKET_NAME_PREFIX=my-build-bucket-name
> for REGION in us-west-2 us-east-1 eu-west-1; do aws s3 create-bucket --bucket $BUCKET_NAME_PREFIX-$REGION --region $REGION; done
```

## CodeBuild (optional)
This repository uses structured (nested) AWS SAM templates and includes buildspecs to use with CodeBuild. If you want to use this method, you'll need to set up a CodeBuild project configured for "batch" builds and point it to this repo (or your own fork). The service role for that CodeBuild project will need permissions for IAM, DDB, Step Functions, Route53, S3, and probably more. Unfortunately, this is not yet documented.

## Deployment Scripts
You can also deploy this solution from the command line if you have the AWS CLI version 2 installed and appropriate credentials configured. The scripts folder contains everything you need, and is probably easier than CodeBuild if you're just "having a look". Note that the scripts assume that they'll be run from the repository root:

```bash
> ./scripts/checks.sh && ./scripts/deploy-global.sh && ./scripts/deploy-region.sh
```

Once you run the scripts, the global resources will be created in a stack called email-delivery-global, and a stack called `email-delivery` will be ready in `us-west-1`, `us-east-2` and `eu-west-1`.


# Features

This is a work in progress serverless system for receiving email, and it already has some pretty subsstantial advantages (and obvious disadvantages) over typocal "self hosted" setups. Here is what you get:

- Emails arriving at your domains are parsed and the attachments and embedded parts (images) extracted to S3.  
- The location of the message is added to the DDB table along with the date, so there is only one place to look for a record of what emails arrived in each region. 
- The S3 URIs to the message objects and other metadata (subject, sender, to, cc, subject, etc.) are combined into a JSON object which is saved alongside the contents in S3, as well as broadcast to EventBridge for handling in downstream processes.
- Multi-region deployment and latency-based routing in Route53 ensure solid  availability.
- The region-specific domain name list allow you to control where emails are stored for domains (e.g. keeping all email to your .uk domain in Ireland and your .com domain in the US).

You don't get a UI or any kind of client, so instead of using `rmail` you're going to be automatically processing email or using `aws dynamodb query ... | aws s3api ...` commands to read that spam. 

Speaking of spam, for kicks this repository can use the OpenAI API to summarize the email body. To use this feature you'll need to set up an OpenAI account and add an AWS SecretsManager secret called "OPENAPI" with a key "API_TOKEN" and the value being your API token (make sure to use the replication feature to easily make it available in the three regions).  If you don't want to use this feature, just put a placeholder in for the token and it'll work just fine.

# Caveats

Please note that while the resources created by this repository are very inexpensive, they are not free, and in certain circumstances can become expensive. Please be aware of the pricing and take it into consideration.

This solution may not align with your concept of a production-quality stack, as it's a work in progress. It doesn't have managed encryption, relies on AWS for spam protection (which you are responsible for paying for), and doesn't include logging or monitoring, among other things.

Please use this solution at your own risk.

# License
This code is available under the MIT license. If you find it helpful, please consider sending me a note or giving me credit. Enjoy!