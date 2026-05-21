FROM dart:stable AS build
WORKDIR /app
COPY pubspec.yaml analysis_options.yaml ./
RUN dart pub get
COPY bin ./bin
COPY lib ./lib
RUN dart compile exe bin/bootstrap.dart -o /app/bootstrap

FROM public.ecr.aws/lambda/provided:al2023
COPY --from=build /app/bootstrap /var/runtime/bootstrap
ENTRYPOINT ["/var/runtime/bootstrap"]
