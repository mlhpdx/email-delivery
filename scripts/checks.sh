# exit when any command fails
set -e

cfn-lint --non-zero-exit-code error templates/global.template
cfn-lint --non-zero-exit-code error templates/regional.template
cfn-lint --non-zero-exit-code error templates/openai-gateway.template
cfn-lint --non-zero-exit-code error templates/domain-email-delivery.template
