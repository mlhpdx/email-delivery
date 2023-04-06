# exit when any command fails
set -e

# regional resources deploy to each supported region...
aws cloudformation package --template-file templates/regional.template --region us-west-2 --s3-bucket ${BUCKET_NAME_PREFIX}-us-west-2 --s3-prefix ${BUCKET_KEY_PREFIX}/${CODEBUILD_RESOLVED_SOURCE_VERSION} --output-template-file regional-us-west-2.template.packaged --use-json
aws cloudformation package --template-file templates/regional.template --region us-east-1 --s3-bucket ${BUCKET_NAME_PREFIX}-us-east-1 --s3-prefix ${BUCKET_KEY_PREFIX}/${CODEBUILD_RESOLVED_SOURCE_VERSION} --output-template-file regional-us-east-1.template.packaged --use-json
aws cloudformation package --template-file templates/regional.template --region eu-west-1 --s3-bucket ${BUCKET_NAME_PREFIX}-eu-west-1 --s3-prefix ${BUCKET_KEY_PREFIX}/${CODEBUILD_RESOLVED_SOURCE_VERSION} --output-template-file regional-eu-west-1.template.packaged --use-json

#get global stack output for EB_ROLE_ARN from EventBridgeRoleArn (in us-west-2)
export EB_ROLE_ARN=$(aws cloudformation describe-stacks --stack-name email-delivery-global --region us-west-2 --query "Stacks[0].Outputs[?OutputKey=='EventBridgeRoleArn'].OutputValue" --output text)
export GLOBAL_TABLE_NAME=$(aws cloudformation describe-stacks --stack-name email-delivery-global --region us-west-2 --query "Stacks[0].Outputs[?OutputKey=='GlobalTableName'].OutputValue" --output text)

aws cloudformation deploy --stack-name email-delivery  --region us-west-2 --template-file regional-us-west-2.template.packaged --no-execute-changeset --parameter-overrides DomainNames=${DOMAIN_NAMES} EventBridgeRoleArn=${EB_ROLE_ARN} Table=${GLOBAL_TABLE_NAME} --capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND
aws cloudformation deploy --stack-name email-delivery  --region us-east-1 --template-file regional-us-east-1.template.packaged --no-execute-changeset --parameter-overrides DomainNames=${DOMAIN_NAMES} EventBridgeRoleArn=${EB_ROLE_ARN} Table=${GLOBAL_TABLE_NAME} --capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND 
aws cloudformation deploy --stack-name email-delivery  --region eu-west-1 --template-file regional-eu-west-1.template.packaged --no-execute-changeset --parameter-overrides DomainNames=${DOMAIN_NAMES} EventBridgeRoleArn=${EB_ROLE_ARN} Table=${GLOBAL_TABLE_NAME} --capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND 
