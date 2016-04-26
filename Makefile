#######################################
#
# Teardown test stack
#
#######################################

destroy:
	bundle exec ./plumbing/db/destroy

#######################################
#
# Setup up test stack
#
#######################################

deploy: .db

.db: Gemfile.lock
	bundle exec ./plumbing/db/create
	touch $@

#######################################
#
# Deploy
#
#######################################

bootstrap: Gemfile.lock

Gemfile.lock: Gemfile
	bundle install --path vendor/bundle

tmp/application_source.zip: tmp/data tmp/Dockerrun.aws.json
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
