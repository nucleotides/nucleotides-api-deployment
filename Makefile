path   := PATH=$(abspath ./vendor/python/bin)
digest := $(shell cd ./tmp/data && git rev-parse HEAD | cut -c1-8)
env    := nucleotides-api-$(digest).zip

s3-bucket := nucleotides-tools
s3-key    := eb-environments/$(env)
s3-url    := s3://$(s3-bucket)/$(s3-key)


deploy-app: .deploy
	$(path) aws elasticbeanstalk update-environment \
		--environment-id ${NUCLEOTIDES_STAGING_ID} \
		--version-label $(env)


db-reset:
	$(path) aws elasticbeanstalk update-environment \
		--environment-id ${NUCLEOTIDES_STAGING_ID} \
		--version-label database-reset

#######################################
#
# Upload elasticbeanstalk data and
# create applicaton version
#
#######################################

.deploy: .upload
	$(path) aws elasticbeanstalk create-application-version \
		--application-name nucleotides \
		--source-bundle 'S3Bucket=$(s3-bucket),S3Key=$(s3-key)' \
		--version-label $(env)

.upload: tmp/$(env)
	$(path) aws s3 cp $< $(s3-url)
	touch $@

#######################################
#
# Build elastic beanstalk config
#
#######################################

tmp/$(env): tmp/data tmp/Dockerrun.aws.json
	cd ./$(dir $@) && zip \
		--recurse-paths \
		--include=data/inputs/* \
		--include=data/controlled_vocabulary/* \
		--include=Dockerrun.aws.json \
		../$@ .

tmp/Dockerrun.aws.json: data/Dockerrun.aws.json
	cp $< $@

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


tmp/data:
	mkdir -p $(dir $@)
	git clone git@github.com:nucleotides/nucleotides-data.git $@
	touch $@

.PHONY: reset
