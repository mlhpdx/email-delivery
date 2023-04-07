# exit when any command fails
set -e

#get global stack output for EB_ROLE_ARN from EventBridgeRoleArn (in us-west-2)
export EB_ROLE_ARN=$(aws cloudformation describe-stacks --stack-name email-delivery-global --region us-west-2 --query "Stacks[0].Outputs[?OutputKey=='EventBridgeRoleArn'].OutputValue" --output text)
export GLOBAL_TABLE_NAME=$(aws cloudformation describe-stacks --stack-name email-delivery-global --region us-west-2 --query "Stacks[0].Outputs[?OutputKey=='GlobalTableName'].OutputValue" --output text)

# source needed for S3UploadStream and SeekableS3Stream; setup credentials in Secret Manager (see the repo readme) 
dotnet nuget add source "https://nuget.pkg.github.com/mlhpdx/index.json" --name "github-mlhpdx" -u ${GITHUB_USERNAME} -p ${GITHUB_TOKEN} --store-password-in-clear-text

# package resources and deploy to each supported region...
sam build --template-file templates/regional.template

sam deploy --s3-bucket ${BUCKET_NAME_PREFIX}-us-west-2 --s3-prefix ${BUCKET_KEY_PREFIX}/email-service/${CODEBUILD_RESOLVED_SOURCE_VERSION} --stack-name email-delivery --parameter-overrides DomainNames="${DOMAIN_NAMES}" EventBridgeRoleArn=${EB_ROLE_ARN} Table=${GLOBAL_TABLE_NAME} --capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND --region us-west-2
sam deploy --s3-bucket ${BUCKET_NAME_PREFIX}-us-east-1 --s3-prefix ${BUCKET_KEY_PREFIX}/email-service/${CODEBUILD_RESOLVED_SOURCE_VERSION} --stack-name email-delivery --parameter-overrides DomainNames="${DOMAIN_NAMES}" EventBridgeRoleArn=${EB_ROLE_ARN} Table=${GLOBAL_TABLE_NAME} --capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND --region us-east-1
sam deploy --s3-bucket ${BUCKET_NAME_PREFIX}-eu-west-1 --s3-prefix ${BUCKET_KEY_PREFIX}/email-service/${CODEBUILD_RESOLVED_SOURCE_VERSION} --stack-name email-delivery --parameter-overrides DomainNames="${DOMAIN_NAMES}" EventBridgeRoleArn=${EB_ROLE_ARN} Table=${GLOBAL_TABLE_NAME} --capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND --region eu-west-1
