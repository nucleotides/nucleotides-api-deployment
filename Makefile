#!/usr/bin/make -f

path           = PATH=$(abspath ./vendor/python/bin)
digest         = $(shell cd ./tmp/data && git rev-parse HEAD | cut -c1-8)
beanstalk-env  = nucleotides-api-$(DEPLOYMENT)-$(digest).zip

s3-bucket = nucleotides-tools
s3-key    = eb-environments/$(beanstalk-env)
s3-url    = s3://$(s3-bucket)/$(s3-key)

ifndef DEPLOYMENT
    $(error DEPLOYMENT variable is undefined)
endif

ifndef DOCKER_HOST
    $(error DOCKER_HOST not found. Docker appears not to be running)
endif

deploy-app: .deploy
	$(path) aws elasticbeanstalk update-environment \
		--environment-id ${NUCLEOTIDES_STAGING_ID} \
		--version-label $(beanstalk-env) \
		| tee > $@


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

tmp/%/.deploy: tmp/%/.upload
	@$(path) aws elasticbeanstalk create-application-version \
		--application-name nucleotides \
		--source-bundle 'S3Bucket=$(s3-bucket),S3Key=$(s3-key)' \
		--version-label $(beanstalk-env) \
		> $@

tmp/%/.upload: tmp/%/beanstalk-deploy.zip
	@$(path) aws s3 cp $< $(s3-url)
	@touch $@

#######################################
#
# Build elastic beanstalk config
#
#######################################

tmp/%/beanstalk-deploy.zip: tmp/data tmp/%/Dockerrun.aws.json
	cd ./$(dir $@) && zip \
		--recurse-paths \
		--include=../data/inputs/* \
		--include=../data/controlled_vocabulary/* \
		--include=Dockerrun.aws.json \
		../../$@ .

tmp/%/Dockerrun.aws.json: data/Dockerrun.aws.json tmp/%/image_digest.txt
	jq \
		--arg image $(shell cat $(lastword $^)) \
		--null-input \
		--from-file $< \
		> $@


tmp/production/image_digest.txt:
	mkdir -p $(dir $@)
	docker pull nucleotides/api:staging
	docker tag nucleotides/api:staging nucleotides/api:master
	docker push nucleotides/api:master \
		| egrep --only-matching '[a-f0-9]{64}' \
		> $@

tmp/staging/image_digest.txt:
	mkdir -p $(dir $@)
	docker pull nucleotides/api:staging \
		| egrep --only-matching '[a-f0-9]{64}' \
		> $@

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

clean:
	rm -rf tmp/*

.PHONY: reset check-env
