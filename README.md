# dav_s3_gateway

Minimal authenticated HTTP file service backed by Amazon S3.

This project intentionally implements a narrow contract:

- `GET` reads one object
- `HEAD` returns object metadata
- `PUT` replaces one object
- Basic Auth protects the endpoint
- request paths map to a fixed S3 bucket prefix

It is designed for low-volume personal use behind API Gateway HTTP API and AWS Lambda.

## Local Development

Install dependencies:

```sh
dart pub get
```

Run the local server:

```sh
export AWS_REGION=ap-northeast-1
export S3_BUCKET=my-private-bucket
export S3_PREFIX=webdav/
export AUTH_MODE=basic
export AUTH_USERNAME=alice
export AUTH_PASSWORD=strong-secret
dart run bin/server.dart
```

The service listens on `HOST` and `PORT` if set, otherwise `0.0.0.0:8080`.

## Environment

Required:

- `AWS_REGION`
- `S3_BUCKET`
- `S3_PREFIX`
- `AUTH_MODE=basic`
- `AUTH_USERNAME`
- `AUTH_PASSWORD`

Optional:

- `MAX_OBJECT_SIZE_BYTES`
- `HOST`
- `PORT`
- `HEALTHCHECK_ENABLED`
- `DAV_S3_GATEWAY_LOG_LEVEL`

AWS credentials are read from the standard runtime variables:

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_SESSION_TOKEN`

In Lambda these normally come from the execution role automatically.

## Behavior

- Unauthenticated requests return `401` and `WWW-Authenticate: Basic realm="dav-s3"`.
- Unsupported methods return `405`.
- Missing objects return `404`.
- Oversized `PUT` requests return `413`.
- Root `/` is not addressable.
- Encoded slashes such as `%2F` are rejected to avoid ambiguous key mapping.

## Testing

```sh
dart test
dart analyze
```

## Lambda Packaging

The repository includes:

- [Dockerfile](Dockerfile) for a Lambda container image
- [infra/template.yaml](infra/template.yaml) as CloudFormation/SAM-style infrastructure scaffolding

The Lambda entrypoint is [bin/bootstrap.dart](bin/bootstrap.dart), which runs a custom runtime loop and converts API Gateway HTTP API v2 events into service requests.
