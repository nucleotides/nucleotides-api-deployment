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
