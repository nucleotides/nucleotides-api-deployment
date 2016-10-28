#!/bin/bash

CONFIG=$1
KEY=$2
ENV=$3

INSTANCE=$(aws elasticbeanstalk describe-environment-resources \
		--environment-id $(jq --raw-output ".${ENV}.id" ${CONFIG}) \
		| jq --raw-output ".EnvironmentResources.Instances[0].Id" \
		| xargs -o -I {} aws ec2 describe-instances --instance-ids {} \
		| jq --raw-output '.Reservations[0].Instances[0].PublicDnsName')

export PGHOST=$(jq --raw-output ".${ENV}.db.url" ${CONFIG}) \
export PGPORT=$(jq --raw-output ".${ENV}.db.port" ${CONFIG}) \
export PGUSER=$(jq --raw-output ".${ENV}.db.username" ${CONFIG}) \
export PGPASSWORD=$(jq --raw-output ".${ENV}.db.password" ${CONFIG}) \

LOCAL_PORT=5433

function finish {
	ssh -S database-socket -O exit ec2-user@${INSTANCE} &> /dev/null
	rm -f database-socket
}
trap finish EXIT

ssh \
	-o "StrictHostKeyChecking no" \
	-i ${HOME}/.ssh/${KEY}.pem \
	-M \
	-S database-socket \
	-N \
	-f \
	-T \
	-L ${LOCAL_PORT}:${PGHOST}:${PGPORT} \
	ec2-user@${INSTANCE} &
sleep 1

ssh -S database-socket -O check ec2-user@${INSTANCE} &> /dev/null

pg_dump \
	--dbname=ebdb \
	--host=localhost \
	--port=${LOCAL_PORT} \
	--username=${PGUSER} \
	--inserts
