path   := PATH=$(abspath ./vendor/python/bin)
digest := $(shell cd ./tmp/data && git rev-parse HEAD | cut -c1-8)
env    := nucleotides-api-$(digest).zip
url    := s3://nucleotides-tools/eb-environments/$(env)


deploy-app:
	$(path) aws elasticbeanstalk update-environment \
		--environment-id ${NUCLEOTIDES_STAGING_ID} \
		--version-label $(env)

deploy-version:
	$(path) aws elasticbeanstalk create-application-version \
		--application-name nucleotides \
		--source-bundle 'S3Bucket=${NUCLEOTIDES_BEAN_BUCKET},S3Key=eb-environments/$(env)' \
		--version-label $(env)

db-reset:
	$(path) aws elasticbeanstalk update-environment \
		--environment-id ${NUCLEOTIDES_STAGING_ID} \
		--version-label database-reset

upload: tmp/$(env)
	$(path) aws s3 cp $< $(url)


#######################################
#
# Bootstrap required resources
#
#######################################

bootstrap: vendor/python tmp/data

vendor/python:
	@mkdir -p log
	@virtualenv $@ 2>&1 > log/virtualenv.txt
	@$(path) pip install awscli==1.10.35
	@touch $@

tmp/$(env): tmp/data tmp/Dockerrun.aws.json
	cd ./$(dir $@) && zip \
		--recurse-paths \
		--include=data/inputs/* \
		--include=data/controlled_vocabulary/* \
		--include=Dockerrun.aws.json \
		../$@ .

tmp/Dockerrun.aws.json: data/Dockerrun.aws.json
	cp $< $@

tmp/data:
	mkdir -p $(dir $@)
	git clone git@github.com:nucleotides/nucleotides-data.git $@
	touch $@

.PHONY: reset
