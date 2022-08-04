# Store tooling in a location that does not affect the system.
GOBIN := $(CURDIR)/.gobin
export GOBIN
PATH := $(GOBIN):$(PATH)
export PATH

SHELL = env GOBIN=$(GOBIN) PATH=$(PATH) /bin/bash
BASE_DIR=$(CURDIR)

TAG := # make sure tag is never injectable as an env var

ifdef CI
ifneq ($(CIRCLE_TAG),)
TAG := $(CIRCLE_TAG)
endif
endif

ifeq ($(TAG),)
TAG=$(shell git describe --tags --abbrev=10 --dirty --long)
endif

LOGLEVEL="${LOGLEVEL:-DEBUG}"

FORMATTING_FILES=$(shell git grep -L '^// Code generated by .* DO NOT EDIT\.' -- '*.go')

DEFAULT_IMAGE_REGISTRY := quay.io/stackrox-io
BUILD_IMAGE_VERSION=$(shell sed 's/\s*\#.*//' BUILD_IMAGE_VERSION)
BUILD_IMAGE := $(DEFAULT_IMAGE_REGISTRY)/apollo-ci:$(BUILD_IMAGE_VERSION)

LOCAL_VOLUME_ARGS := -v$(CURDIR):/src:delegated -v $(GOPATH):/go:delegated
GOPATH_WD_OVERRIDES := -w /src -e GOPATH=/go
IMAGE_BUILD_FLAGS := -e CGO_ENABLED=1,GOOS=linux,GOARCH=amd64
BUILD_FLAGS := CGO_ENABLED=1 GOOS=linux GOARCH=amd64
BUILD_CMD := go build -trimpath -ldflags="-linkmode=external -X github.com/stackrox/scanner/pkg/version.Version=$(TAG)" -o image/scanner/bin/scanner ./cmd/clair

#####################################################################
###### Binaries we depend on (need to be defined on top) ############
#####################################################################

STATICCHECK_BIN := $(GOPATH)/bin/staticcheck
$(STATICCHECK_BIN): deps
	@echo "+ $@"
	@cd tools/linters/ && go install honnef.co/go/tools/cmd/staticcheck

EASYJSON_BIN := $(GOPATH)/bin/easyjson
$(EASYJSON_BIN): deps
	@echo "+ $@"
	go install github.com/mailru/easyjson/easyjson

GOLANGCILINT_BIN := $(GOBIN)/golangci-lint
$(GOLANGCILINT_BIN): deps
	@echo "+ $@"
	@cd tools/linters/ && go install github.com/golangci/golangci-lint/cmd/golangci-lint

OSSLS_BIN := $(GOBIN)/ossls
$(OSSLS_BIN): deps
	@echo "+ $@"
	go install github.com/stackrox/ossls@0.10.1

GO_JUNIT_REPORT_BIN := $(GOBIN)/go-junit-report
$(GO_JUNIT_REPORT_BIN):
	@echo "+ $@"
	@cd tools/test/ && go install github.com/jstemmer/go-junit-report/v2

#############
##  Tag  ##
#############

.PHONY: tag
tag:
	@echo $(TAG)

#############
##  Build  ##
#############
.PHONY: build-updater
build-updater: deps
	@echo "+ $@"
	go build -trimpath -o ./bin/updater ./cmd/updater

###########
## Style ##
###########
.PHONY: style
style: blanks golangci-lint staticcheck no-large-files

.PHONY: staticcheck
staticcheck: $(STATICCHECK_BIN)
	@echo "+ $@"
	@$(BASE_DIR)/tools/staticcheck-wrap.sh ./...

.PHONY: no-large-files
no-large-files:
	@echo "+ $@"
	@$(BASE_DIR)/tools/large-git-files/find.sh

.PHONY: golangci-lint
golangci-lint: $(GOLANGCILINT_BIN) proto-generated-srcs
ifdef CI
	@echo '+ $@'
	@echo 'The environment indicates we are in CI; running linters in check mode.'
	@echo 'If this fails, run `make style`.'
	@echo "Running with no tags..."
	golangci-lint run
	@echo "Running with release tags..."
	@# We use --tests=false because some unit tests don\'t compile with release tags,
	@# since they use functions that we don\'t define in the release build. That\'s okay.
	golangci-lint run --build-tags "$(subst $(comma),$(space),$(RELEASE_GOTAGS))" --tests=false
else
	golangci-lint run --fix
	golangci-lint run --fix --build-tags "$(subst $(comma),$(space),$(RELEASE_GOTAGS))" --tests=false
endif

.PHONY: blanks
blanks:
	@echo "+ $@"
ifdef CI
	@echo $(FORMATTING_FILES) | xargs $(BASE_DIR)/tools/import_validate.py
else
	@echo $(FORMATTING_FILES) | xargs $(BASE_DIR)/tools/fix-blanks.sh
endif

.PHONY: dev
dev: install-dev-tools
	@echo "+ $@"

deps: proto-generated-srcs go.mod
	@echo "+ $@"
	@go mod tidy
ifdef CI
	@git diff --exit-code -- go.mod go.sum || { echo "go.mod/go.sum files were updated after running 'go mod tidy', run this command on your local machine and commit the results." ; exit 1 ; }
	go mod verify
endif
	@touch deps

.PHONY: clean-deps
clean-deps:
	@echo "+ $@"
	@rm -f deps

GET_DEVTOOLS_CMD := $(MAKE) -qp | sed -e '/^\# Not a target:$$/{ N; d; }' | egrep -v '^(\s*(\#.*)?$$|\s|%|\(|\.)' | egrep '^[^[:space:]:]*:' | cut -d: -f1 | sort | uniq | grep '^$(GOPATH)/bin/'
.PHONY: clean-dev-tools
clean-dev-tools:
	@echo "+ $@"
	@$(GET_DEVTOOLS_CMD) | xargs rm -fv

.PHONY: reinstall-dev-tools
reinstall-dev-tools: clean-dev-tools
	@echo "+ $@"
	@$(MAKE) install-dev-tools

.PHONY: install-dev-tools
install-dev-tools:
	@echo "+ $@"
	@$(GET_DEVTOOLS_CMD) | xargs $(MAKE)

############
## Images ##
############

.PHONY: all-images
all-images: image image-slim

.PHONY: image
image: scanner-image db-image

.PHONY: image-slim
image-slim: scanner-image-slim db-image-slim

.PHONY: scanner-build-dockerized
scanner-build-dockerized: deps
	@echo "+ $@"
ifdef CI
	docker container create --name builder $(BUILD_IMAGE) $(BUILD_CMD)
	docker cp $(GOPATH) builder:/
	docker start -i builder
	docker cp builder:/go/src/github.com/stackrox/scanner/image/scanner/bin/scanner image/scanner/bin/scanner
else
	docker run $(IMAGE_BUILD_FLAGS) $(GOPATH_WD_OVERRIDES) $(LOCAL_VOLUME_ARGS) $(BUILD_IMAGE) $(BUILD_CMD)
endif

.PHONY: scanner-build-nodeps
scanner-build-nodeps:
	$(BUILD_FLAGS) $(BUILD_CMD)

.PHONY: $(CURDIR)/image/scanner/rhel/bundle.tar.gz
$(CURDIR)/image/scanner/rhel/bundle.tar.gz:
	$(CURDIR)/image/scanner/rhel/create-bundle.sh $(CURDIR)/image/scanner $(CURDIR)/image/scanner/rhel

.PHONY: $(CURDIR)/image/db/rhel/bundle.tar.gz
$(CURDIR)/image/db/rhel/bundle.tar.gz:
	$(CURDIR)/image/db/rhel/create-bundle.sh $(CURDIR)/image/db $(CURDIR)/image/db/rhel

.PHONY: scanner-image
scanner-image: scanner-build-dockerized ossls-notice $(CURDIR)/image/scanner/rhel/bundle.tar.gz
	@echo "+ $@"
	@docker build -t scanner:$(TAG) -f image/scanner/rhel/Dockerfile image/scanner/rhel

.PHONY: scanner-image-slim
scanner-image-slim: scanner-build-dockerized ossls-notice $(CURDIR)/image/scanner/rhel/bundle.tar.gz
	@echo "+ $@"
	@docker build -t scanner-slim:$(TAG) -f image/scanner/rhel/Dockerfile.slim image/scanner/rhel

.PHONY: db-image
db-image: $(CURDIR)/image/db/rhel/bundle.tar.gz
	@echo "+ $@"
	@test -f image/db/dump/definitions.sql.gz || { echo "FATAL: No definitions dump found in image/dump/definitions.sql.gz. Exiting..."; exit 1; }
	@docker build -t scanner-db:$(TAG) -f image/db/rhel/Dockerfile image/db/rhel

.PHONY: db-image-slim
db-image-slim: $(CURDIR)/image/db/rhel/bundle.tar.gz
	@echo "+ $@"
	@test -f image/db/dump/definitions.sql.gz || { echo "FATAL: No definitions dump found in image/dump/definitions.sql.gz. Exiting..."; exit 1; }
	@docker build -t scanner-db-slim:$(TAG) -f image/db/rhel/Dockerfile.slim image/db/rhel

.PHONY: deploy
deploy: clean-helm-rendered
	@echo "+ $@"
	kubectl create namespace stackrox || true
	helm template scanner chart/ --set tag=$(TAG),logLevel=$(LOGLEVEL),updateInterval=2m --output-dir rendered-chart
	kubectl apply -R -f rendered-chart

.PHONY: slim-deploy
slim-deploy: clean-helm-rendered
	@echo "+ $@"
	kubectl create namespace stackrox || true
	helm template scanner chart/ --set scannerImage=quay.io/stackrox-io/scanner-slim,scannerDBImage=quay.io/stackrox-io/scanner-db-slim,tag=$(TAG),logLevel=$(LOGLEVEL),updateInterval=2m --output-dir rendered-chart
	kubectl apply -R -f rendered-chart

# deploy-local deploys locally-built full-images (i.e. stackrox/scanner:<TAG> and stackrox/scanner-db:<TAG>)
.PHONY: deploy-local
deploy-local: clean-helm-rendered
	@echo "+ $@"
	kubectl create namespace stackrox || true
	helm template scanner chart/ --set tag=$(TAG),logLevel=$(LOGLEVEL),updateInterval=2m,scannerImage=stackrox/scanner,scannerDBImage=stackrox/scanner-db --output-dir rendered-chart
	kubectl apply -R -f rendered-chart

.PHONY: ossls-notice
ossls-notice: deps
	ossls version
	ossls audit --export image/scanner/rhel/THIRD_PARTY_NOTICES

###########
## Tests ##
###########

.PHONY: test-prep
test-prep:
	@echo "+ $@"
	@mkdir -p test-output

.PHONY: unit-tests
unit-tests: deps test-prep
	@echo "+ $@"
	set -o pipefail ; \
	go test -race -v ./... | tee test-output/test.log

.PHONY: e2e-tests
e2e-tests: deps test-prep
	@echo "+ $@"
	set -o pipefail ; \
	go test -tags e2e -count=1 -timeout=20m -v ./e2etests/... | tee test-output/test.log

.PHONY: slim-e2e-tests
slim-e2e-tests: deps test-prep
	@echo "+ $@"
	set -o pipefail ; \
	go test -tags slim_e2e -count=1 -timeout=20m -v ./e2etests/... | tee test-output/test.log

.PHONY: db-integration-tests
db-integration-tests: deps test-prep
	@echo "+ $@"
	set -o pipefail ; \
	go test -tags db_integration -count=1 -v ./database/pgsql | tee test-output/test.log

.PHONY: slim-db-integration-tests
slim-db-integration-tests: deps test-prep
	@echo "+ $@"
	set -o pipefail ; \
	go test -tags slim_db_integration -count=1 -v ./database/pgsql | tee test-output/test.log

.PHONY: scale-tests
scale-tests: deps
	@echo "+ $@"
	mkdir /tmp/pprof
	mkdir /tmp/pprof-out
	go run ./scale/... /tmp/pprof || true
	zip -r /tmp/pprof-out/pprof.zip /tmp/pprof

.PHONY: report
report: $(GO_JUNIT_REPORT_BIN)
	@echo "+ $@"
	@cat test.log | go-junit-report > report.xml
	@mkdir -p $(JUNIT_OUT)
	@cp test.log report.xml $(JUNIT_OUT)
	@echo
	@echo "Test coverage summary:"
	@grep "^coverage: " -A1 test.log | grep -v -e '--' | paste -d " "  - -
	@echo
	@echo "Test pass/fail summary:"
	@grep failures report.xml
	@echo
	@echo "`grep 'FAIL	github.com/stackrox/scanner' test.log | wc -l` package(s) detected with compilation or test failures."
	@-grep 'FAIL	github.com/stackrox/scanner' test.log || true
	@echo
	@testerror="$$(grep -e 'can.t load package' -e '^# github.com/stackrox/scanner/' -e 'FAIL	github.com/stackrox/scanner' test.log | wc -l)" && test $$testerror -eq 0

generate-junit-reports: $(GO_JUNIT_REPORT_BIN)
	$(BASE_DIR)/scripts/generate-junit-reports.sh

####################
## Generated Srcs ##
####################

PROTO_GENERATED_SRCS = $(GENERATED_PB_SRCS) $(GENERATED_API_GW_SRCS)

include make/protogen.mk

.PHONY: clean-obsolete-protos
clean-obsolete-protos:
	@echo "+ $@"
	$(BASE_DIR)/tools/clean_autogen_protos.py --protos $(BASE_DIR)/proto --generated $(BASE_DIR)/generated

proto-generated-srcs: $(PROTO_GENERATED_SRCS)
	@echo "+ $@"
	@touch proto-generated-srcs
	@$(MAKE) clean-obsolete-protos

.PHONY: go-easyjson-srcs
go-easyjson-srcs: $(EASYJSON_BIN)
	@echo "+ $@"
	@easyjson -pkg pkg/vulnloader/nvdloader
	@easyjson -pkg api/v1

clean-proto-generated-srcs:
	@echo "+ $@"
	git clean -xdf generated

###########
## Clean ##
###########
.PHONY: clean
clean: clean-image clean-helm-rendered clean-proto-generated-srcs clean-pprof clean-test
	@echo "+ $@"

.PHONY: clean-image
clean-image:
	@echo "+ $@"
	git clean -xdf image/bin

.PHONY: clean-helm-rendered
clean-helm-rendered:
	@echo "+ $@"
	git clean -xdf rendered-chart

.PHONY: clean-pprof
clean-pprof:
	@echo "+ $@"
	rm /tmp/pprof.zip || true
	rm -rf /tmp/pprof

.PHONY: clean-test
clean-test:
	@echo "+ $@"
	rm -rf test-output/
	rm -rf junit-reports/

##################
## Genesis Dump ##
##################

# Generate and update the scanner genesis dump.  It assumes ``gsutil`` is setup
# properly.  Example:
#
#     make genesis-dump-all WORKFLOW=<update-dumps-hourly-workflow-id>
#

gd-param-workflow := WORKFLOW

gd-target := genesis-dump
gd-base := genesis-dump
gd-dir := $(gd-base)/$($(gd-param-workflow))

gd-manifest-file := image/scanner/dump/genesis_manifests.json
gd-bucket-dump := gs://stackrox-scanner-ci-vuln-dump


.PHONY: $(gd-target) $(gd-target)-commit $(gd-target)-all

$(gd-target)-all: $(gd-target) $(gd-target)-commit

$(gd-target): $(gd-dir)/manifest.json $(gd-dir)/until
	@echo "MANIFEST:"
	@diff -u $(gd-manifest-file) $< | sed 's/^/    /'
	@echo "Run \`make $(gd-target)-commit [...]\` to submit to gcloud and commit."

$(gd-target)-commit: $(gd-dir)/manifest.json $(gd-dir)/gcloud
	! git status --porcelain | grep '^[^? ]'
	cp $< $(gd-manifest-file)
	git add $(gd-manifest-file)
	git checkout -b genesis-dump/$$(cat $(gd-dir)/until | sed 's/T.*//')
	git commit -v -m "New Genesis Dump $$(cat $(gd-dir)/until | sed 's/T.*//')"

$(gd-dir)/gcloud: $(gd-dir)/dest $(gd-dir)/dump.zip
	gsutil cp $(gd-dir)/dump.zip $$(cat $<)
	gsutil retention event set $$(cat $<)
	touch $@

$(gd-dir)/manifest.json: $(gd-dir)/dest $(gd-dir)/uuid $(gd-dir)/until
	git show HEAD:$(gd-manifest-file) \
	    | jq '.knownGenesisDumps += [{"dumpLocationInGS": "'$$(cat $(gd-dir)/dest)'", "timestamp": "'$$(cat $(gd-dir)/until)'", "uuid": "'$$(cat $(gd-dir)/uuid)'"}]' \
	      > $@

$(gd-dir)/dest: $(gd-dir)/until $(gd-dir)/dump.zip
	echo $(gd-bucket-dump)/genesis-$$(cat $< | sed 's/\..*//; s/[:T-]//g').zip > $@

$(gd-dir)/until: $(gd-dir)/dump.zip
	unzip -p $< manifest.json | jq -r .until > $@

$(gd-dir)/dump.zip:
	mkdir -p $(dir $@)
	orig=$$(gsutil ls "gs://roxci-artifacts/scanner/$$(basename $(dir $@))" \
	            | grep generate-genesis-dump) && \
	    gsutil cp $${orig%/}/genesis-dump.zip $@

$(gd-dir)/uuid:
ifndef $(gd-param-workflow)
	@echo "$(gd-param-workflow) was not specified, use \`make $@ $(gd-param-workflow)=<workflow-id>\`"
	@exit 1
else
	mkdir -p $(dir $@)
	uuidgen | tr '[:upper:]' '[:lower:]' > $@
endif
