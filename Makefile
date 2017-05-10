#!/usr/bin/make -f

key  = jgi-macbook-pro

path           = PATH=$(abspath ./vendor/python/bin):/usr/local/bin:/usr/bin:/bin
data-digest    = $(shell cd ./tmp/data && git rev-parse HEAD | cut -c1-8)
image-digest   = $(shell cat tmp/$*/image_digest.txt | cut -c1-8)
beanstalk-env  = nucleotides-api-$*-data-$(data-digest)-image-$(image-digest).zip

s3-bucket = nucleotides-tools
s3-key    = eb-environments/$(beanstalk-env)
s3-url    = s3://$(s3-bucket)/$(s3-key)

ifndef DOCKER_HOST
    $(error DOCKER_HOST not found. Docker appears not to be running)
endif

.PHONY: clean
.SECONDARY:

help:
	@echo "make production    Deploy updates to the producton environment"
	@echo "make staging       Deploy updates to the staging environment"
	@echo "make db-reset      Reset the database in the staging environment"
	@echo
	@echo "make local	  Create local instance of application"
	@echo

staging: tmp/staging/.deploy-app
production: tmp/production/.deploy-app
local: .api_container


#######################################
#
# Create local version of API
#
#######################################

docker_host := $(shell echo ${DOCKER_HOST} | egrep -o "\d+.\d+.\d+.\d+")

# Fake user created for testing database
db_user := PGUSER=postgres
db_pass := PGPASSWORD=pass
db_name := PGDATABASE=postgres
db_host := PGHOST=$(docker_host)
db_port := PGPORT=5433


# Makefile macro shortcut to run docker images with all credentials configured.
docker_db := docker run \
	--env="$(db_user)" \
	--env="$(db_pass)" \
	--env="$(db_name)" \
	--env="$(db_host)" \
	--env="$(db_port)" \
	#--volume=$(abspath tmp/data/db_fixture):/data:ro \


# Launch nucleotides API container, connnected to the RDS container
.api_container: .rdm_loaded .api_image
	@printf $(WIDTH) "  --> Launching nucleotid.es API container"
	@$(docker_db) \
		--detach=true \
		--net=host \
		--publish 80:80 \
		nucleotides/api:master \
		server > $@
	@$(OK)

# Populate local database with contents of master DB
.rdm_loaded: .rdm_container tmp/local/database.sql
	@printf $(WIDTH) "  --> Populating local DB with production data"
	@$(docker_db) \
		--volume="$(abspath $(dir $(lastword $^))):/data:ro" \
		--entrypoint=psql \
		kiasaki/alpine-postgres:9.5 \
		-f /data/database.sql \
		> /dev/null
	@$(OK)


tmp/local/database.sql: tmp/production/database.sql
	@printf $(WIDTH) "  --> Create local version of production DB"
	@mkdir -p $(dir $@)
	@sed '/OWNER TO/s/nucleotides/postgres/p' $< \
		| sed '/Owner:/s/nucleotides/postgres/p' \
		> $@
	@$(OK)


# Launch POSTGRES container
.rdm_container: .rdm_image
	@printf $(WIDTH) "  --> Launching POSTGRES RDS container"
	@docker run \
		--env="$(db_user)" \
		--env="$(db_pass)" \
		--publish=5433:5432 \
		--detach=true \
		kiasaki/alpine-postgres:9.5 \
		> $@
	@sleep 3
	@$(OK)

.api_image:
	@printf $(WIDTH) "  --> Fetching nucleotid.es API Docker image"
	@docker pull nucleotides/api:master 2>&1 > /dev/null
	@touch $@
	@$(OK)

.rdm_image:
	@printf $(WIDTH) "  --> Fetching Postgres RDS Docker image"
	@docker pull kiasaki/alpine-postgres:9.5 2>&1 > /dev/null
	@touch $@
	@$(OK)

#######################################
#
# Deploying applications
#
#######################################


tmp/%/.deploy-app: tmp/environments.json tmp/%/.deploy-bundle tmp/%/.db-backup
	@printf $(WIDTH) "  --> Deploying new $* environment"
	@$(path) aws elasticbeanstalk update-environment \
		--environment-id $(shell jq '.$*.id' $<) \
		--version-label $(beanstalk-env) \
		| tee > $@
	@$(OK)


tmp/%/.db-backup: tmp/%/database.sql.gz
	@printf $(WIDTH) "  --> Backing up $* database to S3"
	@$(path) aws s3 cp $< s3://$(s3-bucket)/backups/$*/database-$(shell date +%s).sql.gz &> /dev/null
	@touch $@
	@$(OK)

%.gz: %
	@gzip --keep --stdout $< > $@

# Reset the production environment to a blank state
db-reset: tmp/environments.json
	@printf $(WIDTH) "  --> Reseting staging environment database to clean state"
	@$(path) aws elasticbeanstalk update-environment \
		--environment-id $(shell jq '.staging.id' $<) \
		--version-label database-reset \
		| tee > $@
	@$(OK)

#######################################
#
# Upload elasticbeanstalk data and
# create applicaton version
#
#######################################

tmp/%/.deploy-bundle: ./bin/update-application-version.sh tmp/%/.upload
	@printf $(WIDTH) "  --> Updating $* elastic beanstalk application version"
	@$(path) $< $(s3-bucket) $(beanstalk-env) > $@
	@touch $@
	@$(OK)

tmp/%/.upload: tmp/%/beanstalk-deploy.zip
	@printf $(WIDTH) "  --> Uploading $* elastic beanstalk deploy bundle"
	@$(path) aws s3 cp $< $(s3-url) &> /dev/null
	@touch $@
	@$(OK)

#######################################
#
# Build elastic beanstalk config
#
#######################################

tmp/%/beanstalk-deploy.zip: tmp/%/data tmp/%/Dockerrun.aws.json
	@printf $(WIDTH) "  --> Creating $* elastic beanstalk deploy bundle"
	@cd ./$(dir $@) && zip \
		--recurse-paths \
		--include=data/inputs/* \
		--include=data/controlled_vocabulary/* \
		--include=Dockerrun.aws.json \
		$(notdir $@) . \
		&> /dev/null
	@$(OK)

tmp/%/Dockerrun.aws.json: data/Dockerrun.aws.json tmp/%/image_digest.txt
	@printf $(WIDTH) "  --> Creating $* elastic beanstalk configuration"
	@jq \
		--arg image $(shell cat $(lastword $^)) \
		--null-input \
		--from-file $< \
		> $@
	@$(OK)


tmp/production/image_digest.txt: tmp/staging/image_digest.txt
	@printf $(WIDTH) "  --> Pushing staging API image to master"
	@mkdir -p $(dir $@)
	@docker tag nucleotides/api:staging nucleotides/api:master
	@docker push nucleotides/api:master \
		| egrep --only-matching '[a-f0-9]{64}' \
		> $@
	@$(OK)

tmp/staging/image_digest.txt:
	@printf $(WIDTH) "  --> Fetching staging API image digest"
	@mkdir -p $(dir $@)
	@docker pull nucleotides/api:staging \
		| egrep --only-matching '[a-f0-9]{64}' \
		> $@
	@$(OK)

tmp/%/data: tmp/data
	@mkdir -p tmp/$*
	@cp -r $< $@

#######################################
#
# Bootstrap required resources
#
#######################################

bootstrap: vendor/python tmp/data tmp/environments.json


tmp/%/database.sql: bin/fetch-database-contents.sh tmp/environments.json
	@printf $(WIDTH) "  --> Fetching current $* database state"
	@mkdir -p $(dir $@)
	@$(path) ./$^ $(key) $* > $@
	@$(OK)

tmp/environments.json: vendor/python
	@printf $(WIDTH) "  --> Fetching AWS environment configurations"
	@$(path) aws s3 cp s3://nucleotides-tools/credentials/environments.json $@ &> /dev/null
	@$(OK)


vendor/python:
	@printf $(WIDTH) "  --> Installing AWS CLI"
	@mkdir -p log
	@virtualenv $@ 2>&1 > log/virtualenv.txt
	@$(path) pip install awscli==1.10.35 2>&1 > log/virtualenv.txt
	@touch $@
	@$(OK)


tmp/data:
	@printf $(WIDTH) "  --> Fetching nucleotides input data"
	@mkdir -p $(dir $@)
	@git clone git@github.com:nucleotides/nucleotides-data.git $@ &> /dev/null
	@touch $@
	@$(OK)

clean:
	@docker kill $(shell cat .rdm_container 2> /dev/null) 2> /dev/null; true
	@docker kill $(shell cat .api_container 2> /dev/null) 2> /dev/null; true
	@rm -f .*_container .*_image
	rm -rf tmp/*

################################################
#
# Colours to format makefile target outputs
#
################################################

OK=echo " $(GREEN)OK$(END)"
WIDTH="%-70s"

RED="\033[0;31m"
GREEN=\033[0;32m
YELLOW="\033[0;33m"
END=\033[0m
