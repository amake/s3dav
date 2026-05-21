lambda_arch ?= arm64

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
	dart compile exe \
		--target-os linux \
		--target-arch $(lambda_arch) \
		bin/bootstrap.dart \
		-o dist/bootstrap

.PHONY: docker-build
docker-build:
	docker build -t dav_s3_gateway .
