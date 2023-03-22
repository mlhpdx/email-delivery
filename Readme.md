# Sending and Receiving Email with SES

Per the [accompanying article](https://medium.com/@lee.harding/how-to-be-an-email-deadbeat-b3e4071ef600) article, this repo implements inexpensive (effectively free), low volume in- and out-bound email for domains. Inbound emails are parsed, enhanced and generate EventBridge events to support triggering automated email-based workflows.

I built this as an alternative to Gmail, which is more expensive and kind of bad fit for my needs anyway.  If you maintain multiple domains that benefit from email service and you're confortable moving your email service to AWS SES and living without a fancy web UI, you might find this repo helpful and/or informative.

This repo deploys email service in the three AWS regions that support SES email delivery (`us-west-2`, `us-east-1` and `eu-east-1`) and configures Route53 latency based routing so clients make use of geographically "local" services. An added benefit here is that your email will continue to work if/when an entire AWS region goes down. It uses an DynamoDB table with replication in those regions to hold "mailbox" metadata.

This repo also uses OpenAI ChatGPT-3 to summarize the email body, so for the state machine to run cleanly you'll need to setup an OpenAI account and add an AWS SecretsManager secret called "OPENAPI" with a key "API_TOKEN" and the value being your API token (it'll need to be present in each region above). Or you can simply delete the two nodes that deal with that, since it's basically gratuitous. 

## Deploying and Using

First off, the domain names in the repo are hard-coded to "foo.com" and "bar.com" and while it will deploy to any account using those names, you won't really be able to use it.  You'll very likely want to fork this repo and edit/add/remove domains. If you have two domains, just find and replace "foo.com" and "bar.com".  If you want to add more domains you'll need to search for uses of the Domain1 and Domain2 parameters and duplicate the appropriate resources for your new Domain3, Domain4, and so on. It's pretty easy to do, so don't be afraid.

Before the deployments will work you'll need to manually create hosted zones for the domains you're using. Default, empty zones are fine.

This repo uses structured (nested) AWS SAM templates, and includes buildspecs to use with codebuild.  If you want to go that route you'll need to setup a CodeBuild project configured for "batch" builds and point it to your fork. The service role for that codebuild project will need permissions for DDB, Step Functions, Route53, S3, and probably more I'm forgetting.  I probably should document that -- sorry.

This report also includes a Lambda function running on .Net.  So you'll also need to have the .Net 6 SDK installed. 

You can also deploy this solution from the command line (if you have the AWS CLI version 2 installed and appropriate credentials configured). The scripts folder contains what you need, and is probably easier than codebuild if you're just "having a look". NOTE: The scripts assume that they'll be run from the repo root:

```bash
> ./scripts/checks.sh && ./scripts/deploy-global.sh && ./scripts/deploy-region.sh
```

Once they run the global resources will be created in a stack called `email-delivery-global`, and change sets will be ready in `us-west-1`, `us-east-2` and `eu-west-1` for the stack `email-delivery` -- you'll need to execute them manually.

With those in place, when someone sends an email to your postmaster@ address it will end up in the matching folder in S3 while all other email address at the same domain will end up in the folder with just the domain name.

## Caveats

AWS is not free, so be aware of the pricing and take that into consideration.  The resources created by this repo are very inexpensive, but not free and in certain circumstances can become expensive.  

Also, this isn't a production quality stack -- it's a work in progress. It doesn't have managed (any?) encryption, relies on AWS for spam protection (which you are on the hook to pay for), doesn't include logging or monitoring, etc.  

Use at your own risk.
