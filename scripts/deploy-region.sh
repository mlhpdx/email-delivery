# exit when any command fails
set -e

# could also use the SAM cli
dotnet tool install -g Amazon.Lambda.Tools

# source needed for S3UploadStream and SeekableS3Stream; setup credentials in Secret Manager (see the repo readme) 
dotnet nuget add source "https://nuget.pkg.github.com/mlhpdx/index.json" --name "github-mlhpdx" -u ${GITHUB_USERNAME} -p ${GITHUB_TOKEN} --store-password-in-clear-text

# package resources to deploy to each supported region...
dotnet lambda package-ci --template templates/regional.template --region us-west-2 --s3-bucket ${BUCKET_NAME_PREFIX}-us-west-2 --s3-prefix ${BUCKET_KEY_PREFIX}/${CODEBUILD_RESOLVED_SOURCE_VERSION} --output-template regional-us-west-2.template.packaged --use-json
dotnet lambda package-ci --template templates/regional.template --region us-east-1 --s3-bucket ${BUCKET_NAME_PREFIX}-us-east-1 --s3-prefix ${BUCKET_KEY_PREFIX}/${CODEBUILD_RESOLVED_SOURCE_VERSION} --output-template regional-us-east-1.template.packaged --use-json
dotnet lambda package-ci --template templates/regional.template --region eu-west-1 --s3-bucket ${BUCKET_NAME_PREFIX}-eu-west-1 --s3-prefix ${BUCKET_KEY_PREFIX}/${CODEBUILD_RESOLVED_SOURCE_VERSION} --output-template regional-eu-west-1.template.packaged --use-json

#get global stack output for EB_ROLE_ARN from EventBridgeRoleArn (in us-west-2)
export EB_ROLE_ARN=$(aws cloudformation describe-stacks --stack-name email-delivery-global --region us-west-2 --query "Stacks[0].Outputs[?OutputKey=='EventBridgeRoleArn'].OutputValue" --output text)
export GLOBAL_TABLE_NAME=$(aws cloudformation describe-stacks --stack-name email-delivery-global --region us-west-2 --query "Stacks[0].Outputs[?OutputKey=='GlobalTableName'].OutputValue" --output text)

# run deploys to each supported region...
aws cloudformation deploy --stack-name email-delivery  --region us-west-2 --template-file regional-us-west-2.template.packaged --no-execute-changeset --parameter-overrides DomainNames="${DOMAIN_NAMES}" EventBridgeRoleArn=${EB_ROLE_ARN} Table=${GLOBAL_TABLE_NAME} --capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND
aws cloudformation deploy --stack-name email-delivery  --region us-east-1 --template-file regional-us-east-1.template.packaged --no-execute-changeset --parameter-overrides DomainNames="${DOMAIN_NAMES}" EventBridgeRoleArn=${EB_ROLE_ARN} Table=${GLOBAL_TABLE_NAME} --capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND 
aws cloudformation deploy --stack-name email-delivery  --region eu-west-1 --template-file regional-eu-west-1.template.packaged --no-execute-changeset --parameter-overrides DomainNames="${DOMAIN_NAMES}" EventBridgeRoleArn=${EB_ROLE_ARN} Table=${GLOBAL_TABLE_NAME} --capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND 
