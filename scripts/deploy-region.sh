# exit when any command fails
set -e

#get global stack output for EB_ROLE_ARN from EventBridgeRoleArn (in us-west-2)
export EB_ROLE_ARN=$(aws cloudformation describe-stacks \
  --stack-name email-delivery-global \
  --region us-west-2 \
  --query "Stacks[0].Outputs[?OutputKey=='EventBridgeRoleArn'].OutputValue" \
  --output text)
export GLOBAL_TABLE_NAME=$(aws cloudformation describe-stacks \
  --stack-name email-delivery-global \
  --region us-west-2 \
  --query "Stacks[0].Outputs[?OutputKey=='GlobalTableName'].OutputValue" \
  --output text)

# package resources and deploy to each supported region...
sam build --template-file templates/regional.template

# if not otherwise specified, the three default regions are used
if [[ -n "$DEPLOY_TO_REGIONS" ]]; then
  export DEPLOY_TO_REGIONS="us-west-2 us-east-1 eu-west-1"
  exit 1
fi

for DEPLOY_REGION in $DEPLOY_TO_REGIONS; do
  sam deploy \
    --s3-bucket ${BUCKET_NAME_PREFIX}-${DEPLOY_REGION} \
    --s3-prefix ${BUCKET_KEY_PREFIX}/email-service/${CODEBUILD_RESOLVED_SOURCE_VERSION} \
    --stack-name email-delivery \
    --parameter-overrides \
      "DomainNames=${DOMAIN_NAMES}" \
      EventBridgeRoleArn=${EB_ROLE_ARN} \
      Table=${GLOBAL_TABLE_NAME} \
    --capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND \
    --region ${DEPLOY_REGION}
done