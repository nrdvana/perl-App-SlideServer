FROM alpine:latest

RUN apk add --no-cache perl gcc make musl-dev

RUN apk add --no-cache perl-app-cpanminus perl-mojolicious perl-log-any perl-dev perl-module-build perl-file-pushd

RUN cpanm Log::Any::Adapter::Daemontools Text::Markdown::Hoedown \
 && rm -rf ~/.cpanm

COPY slide-server.pl /app/
COPY slides_example.html /app/
COPY public /app/public/

EXPOSE 80

ENTRYPOINT ["/usr/bin/env"]
CMD ["perl","/app/slide-server.pl","daemon","-m","production","-l","http://*:80"]
