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
cf_hosted_zone_id := $(if $(hosted_zone_id),HostedZoneId=$(hosted_zone_id),)

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
	@echo "artifact_bucket=$(artifact_bucket)"
	@echo "artifact_key=$(artifact_key)"
	@echo "domain_name=$(domain_name)"
	@echo "certificate_arn=$(certificate_arn)"
	@echo "hosted_zone_id=$(hosted_zone_id)"
	@echo "s3_bucket=$(s3_bucket)"
	@echo "s3_prefix=$(s3_prefix)"
	@echo "auth_username=$(auth_username)"
	@echo "max_object_size_bytes=$(max_object_size_bytes)"

.PHONY: upload
upload: $(payload)
	@test -n "$(artifact_bucket)" || (echo "artifact_bucket is required" && exit 1)
	aws s3 cp $(payload) s3://$(artifact_bucket)/$(artifact_key)

.PHONY: deploy
deploy: upload
	@test -n "$(domain_name)" || (echo "domain_name is required" && exit 1)
	@test -n "$(certificate_arn)" || (echo "certificate_arn is required" && exit 1)
	@test -n "$(s3_bucket)" || (echo "s3_bucket is required" && exit 1)
	@test -n "$(s3_prefix)" || (echo "s3_prefix is required" && exit 1)
	@test -n "$(auth_username)" || (echo "auth_username is required" && exit 1)
	@test -n "$(auth_password)" || (echo "auth_password is required" && exit 1)
	aws cloudformation deploy \
		--stack-name $(stack_name) \
		--template-file $(template) \
		--capabilities CAPABILITY_NAMED_IAM \
		--parameter-overrides \
			ServiceName=$(service_name) \
			ArtifactBucket=$(artifact_bucket) \
			ArtifactKey=$(artifact_key) \
			DomainName=$(domain_name) \
			CertificateArn=$(certificate_arn) \
			$(cf_hosted_zone_id) \
			S3Bucket=$(s3_bucket) \
			S3Prefix=$(s3_prefix) \
			AuthUsername=$(auth_username) \
			AuthPassword=$(auth_password) \
			MaxObjectSizeBytes=$(max_object_size_bytes)
