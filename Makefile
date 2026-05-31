deploy_config ?= deploy.env
ifneq ("$(wildcard $(deploy_config))","")
include $(deploy_config)
export
endif

lambda_arch ?= arm64
payload := dist/lambda.zip
bootstrap := dist/bootstrap
template := infra/template.yaml
stack_name ?= dav-s3-gateway
service_name ?= dav-s3-gateway
artifact_key ?= $(service_name)/lambda.zip
max_object_size_bytes ?= 5242880
s3_region ?= $(aws_region)
cf_hosted_zone_id := $(if $(hosted_zone_id),HostedZoneId=$(hosted_zone_id),)
aws_region_arg := $(if $(aws_region),--region $(aws_region),)
certificate_region = $(word 4,$(subst :, ,$(certificate_arn)))

.PHONY: deps
deps:
	dart pub get

.PHONY: test
test:
	dart test

.PHONY: analyze
analyze:
	dart analyze

.PHONY: lint
lint: analyze
	dart format --set-exit-if-changed .

.PHONY: run
run:
	dart run bin/server.dart

.PHONY: build-bootstrap
build-bootstrap:
	mkdir -p dist
	dart compile exe \
		--target-os linux \
		--target-arch $(lambda_arch) \
		bin/bootstrap.dart \
		-o $(bootstrap)

$(payload): build-bootstrap
	rm -f $(payload)
	cd dist && zip -9 lambda.zip bootstrap

.PHONY: build
build: $(payload)

.PHONY: show-config
show-config:
	@echo "deploy_config=$(deploy_config)"
	@echo "stack_name=$(stack_name)"
	@echo "service_name=$(service_name)"
	@echo "aws_region=$(aws_region)"
	@echo "artifact_bucket=$(artifact_bucket)"
	@echo "artifact_key=$(artifact_key)"
	@echo "domain_name=$(domain_name)"
	@echo "certificate_arn=$(certificate_arn)"
	@echo "certificate_region=$(certificate_region)"
	@echo "hosted_zone_id=$(hosted_zone_id)"
	@echo "s3_bucket=$(s3_bucket)"
	@echo "s3_region=$(s3_region)"
	@echo "s3_prefix=$(s3_prefix)"
	@echo "auth_username=$(auth_username)"
	@echo "max_object_size_bytes=$(max_object_size_bytes)"

.PHONY: upload
upload: $(payload)
	@test -n "$(artifact_bucket)" || (echo "artifact_bucket is required" && exit 1)
	@test -n "$(aws_region)" || (echo "aws_region is required" && exit 1)
	aws $(aws_region_arg) s3 cp $(payload) s3://$(artifact_bucket)/$(artifact_key)

.PHONY: deploy
deploy: upload
	@test -n "$(aws_region)" || (echo "aws_region is required" && exit 1)
	@test -n "$(domain_name)" || (echo "domain_name is required" && exit 1)
	@test -n "$(certificate_arn)" || (echo "certificate_arn is required" && exit 1)
	@test "$(certificate_region)" = "$(aws_region)" || (echo "certificate_arn region ($(certificate_region)) must match aws_region ($(aws_region))" && exit 1)
	@test -n "$(s3_bucket)" || (echo "s3_bucket is required" && exit 1)
	@test -n "$(s3_region)" || (echo "s3_region is required" && exit 1)
	@test -n "$(s3_prefix)" || (echo "s3_prefix is required" && exit 1)
	@test -n "$(auth_username)" || (echo "auth_username is required" && exit 1)
	@test -n "$(auth_password)" || (echo "auth_password is required" && exit 1)
	aws $(aws_region_arg) cloudformation deploy \
		--stack-name $(stack_name) \
		--template-file $(template) \
		--capabilities CAPABILITY_NAMED_IAM \
		--no-fail-on-empty-changeset \
		--parameter-overrides \
			ServiceName=$(service_name) \
			ArtifactBucket=$(artifact_bucket) \
			ArtifactKey=$(artifact_key) \
			DomainName=$(domain_name) \
			CertificateArn=$(certificate_arn) \
			$(cf_hosted_zone_id) \
			S3Bucket=$(s3_bucket) \
			S3Region=$(s3_region) \
			S3Prefix=$(s3_prefix) \
			AuthUsername=$(auth_username) \
			AuthPassword=$(auth_password) \
			MaxObjectSizeBytes=$(max_object_size_bytes)
	$(MAKE) update-code

.PHONY: update-code
update-code:
	@test -n "$(artifact_bucket)" || (echo "artifact_bucket is required" && exit 1)
	@test -n "$(artifact_key)" || (echo "artifact_key is required" && exit 1)
	@test -n "$(aws_region)" || (echo "aws_region is required" && exit 1)
	@test -n "$(service_name)" || (echo "service_name is required" && exit 1)
	aws $(aws_region_arg) lambda update-function-code \
		--function-name $(service_name) \
		--s3-bucket $(artifact_bucket) \
		--s3-key $(artifact_key) \
		--publish
