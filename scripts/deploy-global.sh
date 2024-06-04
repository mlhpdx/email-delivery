# exit when any command fails
set -e

# global resources deploy only in us-west-2!
aws cloudformation package \
    --template-file templates/global.template \
    --s3-bucket ${BUCKET_NAME_PREFIX}-us-west-2 \
    --s3-prefix ${BUCKET_KEY_PREFIX}/email-service/${CODEBUILD_RESOLVED_SOURCE_VERSION} \
    --region us-west-2 \
    > global.template.published

aws cloudformation deploy \
    --stack-name email-delivery-global \
    --template-file global.template.published \
    --no-fail-on-empty-changeset \
    --parameter-overrides \
        DomainNames="${DOMAIN_NAMES}" \
    --capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND 
    --region us-west-2
