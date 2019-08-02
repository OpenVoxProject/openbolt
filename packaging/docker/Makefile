NAMESPACE ?= puppet
git_describe = $(shell git describe)
vcs_ref := $(shell git rev-parse HEAD)
build_date := $(shell date -u +%FT%T)
hadolint_available := $(shell hadolint --help > /dev/null 2>&1; echo $$?)
hadolint_command := hadolint --ignore DL3008 --ignore DL3018 --ignore DL4000 --ignore DL4001
hadolint_container := hadolint/hadolint:latest
pwd := $(shell pwd)

# Check if ref is set in environment variable
# REF is set by the CJC build-and-puahs-bolt-docker-image.sh script and 
# is expected to be the Git Tag that represents the
# bolt release version.
ifeq ("${REF}","")
    version := $(shell echo $(git_describe) | sed 's/-.*//')
else
    version:= "${REF}"
endif
$(info VERSION is $(version))
# # Alow bundler args to be configured with environment variables
# # Add defaults based on running from Makefile dir.
ifeq ("${BUNDLE_PATH}","")
	export BUNDLE_PATH=$(pwd)/.bundle/gems
endif
$(info BUNDLE_PATH is "${BUNDLE_PATH}")

ifeq ("${BUNDLE_BIN}","")
	export BUNDLE_BIN=$(pwd)/.bundle/bin
endif
$(info BUNDLE_BIN is "${BUNDLE_BIN}")

ifeq ("${GEMFILE}","")
	export GEMFILE=$(pwd)/Gemfile
endif
$(info GEMFILE is "${GEMFILE}")

dockerfile := Dockerfile

prep:
	@git fetch --unshallow > /dev/null 2>&1 ||:
	@git fetch origin 'refs/tags/*:refs/tags/*'

lint:
ifeq ($(hadolint_available),0)
	@$(hadolint_command) puppet-bolt/$(dockerfile)
else
	@docker pull $(hadolint_container)
	@docker run --rm -v $(PWD)/puppet-bolt/$(dockerfile):/Dockerfile -i $(hadolint_container) $(hadolint_command) Dockerfile
endif

build: prep
	@docker build --pull --build-arg vcs_ref=$(vcs_ref) --build-arg build_date=$(build_date) --build-arg version=$(version) --file puppet-bolt/$(dockerfile) --tag $(NAMESPACE)/puppet-bolt:$(version) puppet-bolt
ifeq ($(IS_LATEST),true)
	@docker tag $(NAMESPACE)/puppet-bolt:$(version) $(NAMESPACE)/puppet-bolt:latest
endif

test: prep
	@bundle install --path $$BUNDLE_PATH --gemfile $$GEMFILE
	@PUPPET_TEST_DOCKER_IMAGE=$(NAMESPACE)/puppet-bolt:$(version) \
		bundle exec rspec puppet-bolt/spec

publish: prep
	@docker push $(NAMESPACE)/puppet-bolt:$(version)
ifeq ($(IS_LATEST),true)
	@docker push $(NAMESPACE)/puppet-bolt:latest
endif

.PHONY: lint build test publish
