#######################################
#
# Bootstrap required resources
#
#######################################

bootstrap: tmp/data

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
