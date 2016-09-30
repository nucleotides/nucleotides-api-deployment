#!/usr/bin/make -f

path           = PATH=$(abspath ./vendor/python/bin):/usr/local/bin
data-digest    = $(shell cd ./tmp/data && git rev-parse HEAD | cut -c1-8)
image-digest   = $(shell cat tmp/$(DEPLOYMENT)/image_digest.txt | cut -c1-8)
beanstalk-env  = nucleotides-api-$(DEPLOYMENT)-data-$(data-digest)-image-$(image-digest).zip

s3-bucket = nucleotides-tools
s3-key    = eb-environments/$(beanstalk-env)
s3-url    = s3://$(s3-bucket)/$(s3-key)

ifndef DEPLOYMENT
    $(error DEPLOYMENT variable is undefined)
endif

ifndef DOCKER_HOST
    $(error DOCKER_HOST not found. Docker appears not to be running)
endif

.PHONY: clean
.PRECIOUS: tmp/%/.deploy-bundle

$(DEPLOYMENT): tmp/$(DEPLOYMENT)/.deploy-app

tmp/%/.deploy-app: tmp/environments.json tmp/%/.deploy-bundle
	@$(path) aws elasticbeanstalk update-environment \
		--environment-id $(shell jq '.$*.id' $<) \
		--version-label $(beanstalk-env) \
		| tee > $@


db-reset: tmp/environments.json
	$(path) aws elasticbeanstalk update-environment \
		--environment-id $(shell jq '.staging.id' $<) \
		--version-label database-reset \
		| tee > $@

#######################################
#
# Upload elasticbeanstalk data and
# create applicaton version
#
#######################################

tmp/%/.deploy-bundle: ./bin/update-application-version.sh tmp/%/.upload
	@$(path) $< $(s3-bucket) $(beanstalk-env) > $@
	touch $@

tmp/%/.upload: tmp/%/beanstalk-deploy.zip
	@$(path) aws s3 cp $< $(s3-url)
	@touch $@

#######################################
#
# Build elastic beanstalk config
#
#######################################

tmp/%/beanstalk-deploy.zip: tmp/%/data tmp/%/Dockerrun.aws.json
	cd ./$(dir $@) && zip \
		--recurse-paths \
		--include=data/inputs/* \
		--include=data/controlled_vocabulary/* \
		--include=Dockerrun.aws.json \
		$(notdir $@) .

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

tmp/%/data: tmp/data
	cp -r $< $@

#######################################
#
# Bootstrap required resources
#
#######################################

bootstrap: vendor/python tmp/data tmp/environments.json

tmp/environments.json: vendor/python
	@$(path) aws s3 cp s3://nucleotides-tools/credentials/environments.json $@

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
