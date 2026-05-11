#!/usr/bin/env bash
set -euo pipefail

OUTPUTS_FILE="${OUTPUTS_FILE:-email-delivery-global.outputs.json}"
if [ -z "${GLOBAL_TABLE_NAME:-}" ]; then
  TABLE=$(jq -r '.[] | select(.OutputKey=="GlobalTableName") | .OutputValue' "$OUTPUTS_FILE")
else
  TABLE="$GLOBAL_TABLE_NAME"
fi
if [ -z "$TABLE" ]; then
  echo "Error: GLOBAL_TABLE_NAME is not set and could not be read from ${OUTPUTS_FILE}" >&2
  exit 1
fi
DATE="${1:-$(date +%Y-%m-%d)}"

echo "Syncing emails for ${DATE}..."

# Get all recipients who received email on this date
RECIPIENTS=$(aws dynamodb query \
  --table-name "$TABLE" \
  --key-condition-expression "PK = :pk" \
  --expression-attribute-values "{\":pk\":{\"S\":\"MSG_CNT|${DATE}\"}}" \
  --query "Items[].SK.S" \
  --output text | tr '\t' '\n')

if [ -z "$RECIPIENTS" ]; then
  echo "No emails found for ${DATE}."
  exit 0
fi

for RECIPIENT in $RECIPIENTS; do
  echo "  Processing ${RECIPIENT}..."

  while IFS=$'\t' read -r MSG_ID PAYLOAD_URI; do
    [ -z "$MSG_ID" ] && continue
    CONTENT_URI="${PAYLOAD_URI/\/inbox\//\/content\/}"
    LOCAL_DIR="./email/${RECIPIENT}/${DATE}"

    mkdir -p "${LOCAL_DIR}/${MSG_ID}"
    echo "    ${MSG_ID}"

    # Original raw email
    aws s3 cp "$PAYLOAD_URI" "${LOCAL_DIR}/${MSG_ID}.eml"

    # Extracted body and attachments
    aws s3 sync "${CONTENT_URI}/" "${LOCAL_DIR}/${MSG_ID}/"

  done < <(aws dynamodb query \
    --table-name "$TABLE" \
    --key-condition-expression "PK = :pk" \
    --expression-attribute-values "{\":pk\":{\"S\":\"MSG|${RECIPIENT}|${DATE}\"}}" \
    --query "Items[].[SK.S, PayloadUri.S]" \
    --output text)
done

echo "Done."
