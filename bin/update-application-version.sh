#!/bin/bash

set -o nounset
set -o errexit

S3_BUCKET=$1
LABEL=$2
S3_KEY="eb-environments/${LABEL}"

EXISTS=$(aws elasticbeanstalk describe-application-versions \
	| jq -r ".ApplicationVersions | map(select(.VersionLabel == \"${LABEL}\")) | . != []")

if [ "${EXISTS}" == "false" ]; then
	aws elasticbeanstalk create-application-version \
		--application-name nucleotides \
		--source-bundle "S3Bucket=${S3_BUCKET},S3Key=${S3_KEY}" \
		--version-label ${LABEL}
fi
