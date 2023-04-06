# Sending and Receiving Email with SES

Per the [accompanying article](https://medium.com/@lee.harding/how-to-be-an-email-deadbeat-b3e4071ef600) article, this repo implements inexpensive (effectively free), low volume in- and out-bound email for domains. Inbound emails are parsed, enhanced and generate EventBridge events to support triggering automated email-based workflows. If you maintain multiple domains that benefit from email service and you're confortable moving your email service to AWS SES and living without a fancy web UI, you might find this repo helpful and/or informative.

The CodeBuild scripts here deploy to the three AWS regions that support SES email receiving (`us-west-2`, `us-east-1` and `eu-east-1`) and configure Route53 latency based routing so clients make use of geographically "local" services. An added benefit here is that your email will continue to work if/when an entire AWS region goes down. It uses a Global DynamoDB table with replication in those regions to hold "mailbox" metadata.

This repo also uses OpenAI ChatGPT-3 to summarize the email body, so you'll need to setup an OpenAI account and add an AWS SecretsManager secret called "OPENAPI" with a key "API_TOKEN" and the value being your API token (it'll need to be present in each region above). Or you can simply delete the two nodes that deal with that, since it's basically gratuitous. 

## Deploying and Using

To deploy this solution you'll need my ["ForEach" cloudformation macro](https://github.com/mlhpdx/cloudformation-macros) installed in your account.  Sorry about that, but using it makes customizing the list of domains much easier and I decided it was worth it for that benefit.

The domain names to enable with email receiving are defined in a parameter store value called `/config/prod/email-delivery/DOMAIN_NAMES`. To use your own list of domains, just add that value (in all three regions) as a comma-seprated list.  If instead you just want to use the defaults of "foo.com" and "bar.com", simply remove the parameter override arguments in `deploy-global.sh` and `deploy-region.sh` (while the project will deploy to any account using those names you won't really be able to use it 'cause someone else owns the name servers).  

Before the deployments you'll need hosted zones for the domains you're using. So create 'em if you don't already have 'em. Default, empty zones are fine.

This repo uses structured (nested) AWS SAM templates, and includes buildspecs to use with codebuild.  If you want to go that route you'll need to setup a CodeBuild project configured for "batch" builds and point it to your fork. The service role for that codebuild project will need permissions for DDB, Step Functions, Route53, S3, and probably more I'm forgetting.  I probably should document that -- sorry.

This report also includes a Lambda function running on .Net.  So you'll also need to have the .Net 6 SDK installed wherever your building it. 

You can also deploy this solution from the command line (if you have the AWS CLI version 2 installed and appropriate credentials configured). The scripts folder contains what you need, and is probably easier than codebuild if you're just "having a look". NOTE: The scripts assume that they'll be run from the repo root:

```bash
> ./scripts/checks.sh && ./scripts/deploy-global.sh && ./scripts/deploy-region.sh
```

Once they run the global resources will be created in a stack called `email-delivery-global`, and change sets will be ready in `us-west-1`, `us-east-2` and `eu-west-1` for the stack `email-delivery` -- you'll need to execute them manually.

With those in place, when someone sends an email to any address at your domains it will end up in S3 and an entry will be created in the DDB table for each address. And, as decribed in the article you'll also see a rich event posted to EventBridge.

## Caveats

AWS is not free, so be aware of the pricing and take that into consideration.  The resources created by this repo are very inexpensive, but not free and in certain circumstances can become expensive.  

Also, this may not align with your concept of a production quality stack -- it's a work in progress. It doesn't have managed (any?) encryption, relies on AWS for spam protection (which you are on the hook to pay for), doesn't include logging or monitoring, etc.  

To make it simple to customize the list of domains, this solution makes use of my cloudformation macro "ForEach". Don't forget to add that to your account or this solution won't deploy.

As always, use at your own risk.

## License

This code is available under the MIT license.  If you find it helpful, consider sending me a note or credit. Enjoy!