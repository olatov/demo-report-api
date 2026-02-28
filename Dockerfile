FROM freepascal/fpc:trunk-bookworm-full AS build

WORKDIR /src
COPY demoreportapi.lpr .
RUN fpc -O3 -XS -XX -CX -o./demoreportapi demoreportapi.lpr

FROM alpine:3.23 AS final
RUN apk --no-cache add libc6-compat

WORKDIR /app
COPY --from=build /src/demoreportapi .
COPY index.html .
COPY circles.png .
COPY LibreFranklin-Medium.ttf .

EXPOSE 5050

CMD ["./demoreportapi"]
