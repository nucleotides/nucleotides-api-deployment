#######################################
#
# Teardown test stack
#
#######################################

destroy:
	terraform destroy --force

#######################################
#
# Setup up test stack
#
#######################################

deploy: variables.tf
	terraform apply

variables.tf: ~/.aws/variables.tf
	cp $< $@
