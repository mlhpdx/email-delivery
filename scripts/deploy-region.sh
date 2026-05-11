# exit when any command fails
set -e -x

#get global stack outputs from file written by deploy-global.sh
OUTPUTS_FILE="${OUTPUTS_FILE:-email-delivery-global.outputs.json}"
export EB_ROLE_ARN=$(jq -r '.[] | select(.OutputKey=="EventBridgeRoleArn") | .OutputValue' "$OUTPUTS_FILE")
export GLOBAL_TABLE_NAME=$(jq -r '.[] | select(.OutputKey=="GlobalTableName") | .OutputValue' "$OUTPUTS_FILE")

# package resources and deploy to each supported region...
sam build --template-file templates/regional.template

for DEPLOY_REGION in ${DEPLOY_TO_REGIONS:-us-west-2 us-east-1 eu-west-1}; do
  sam deploy \
    --s3-bucket ${BUCKET_NAME_PREFIX}-${DEPLOY_REGION} \
    --s3-prefix ${BUCKET_KEY_PREFIX}/email-service/${CODEBUILD_RESOLVED_SOURCE_VERSION} \
    --stack-name email-delivery \
    --parameter-overrides \
      "DomainNames=${DOMAIN_NAMES}" \
      EventBridgeRoleArn=${EB_ROLE_ARN} \
      Table=${GLOBAL_TABLE_NAME} \
      ReplicaRegions=${REPLICA_REGIONS:-us-west-2,us-east-1,eu-west-1} \
    --capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND \
    --region ${DEPLOY_REGION}
done 
