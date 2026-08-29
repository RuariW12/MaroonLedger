# Build once, produce two binaries. `server` is the production target; `devidp`
# is a local-only identity provider and is built only by docker-compose, so a
# plain `docker build .` can never ship it.
FROM golang:1.25-alpine AS builder
WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .
# CGO_ENABLED=0 produces a static binary, which is what allows the runtime
# stage to carry nothing but the binary and CA certificates.
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/server ./cmd/server
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/devidp ./cmd/devidp

FROM alpine:3.19 AS runtime-base
# TLS roots are required to reach Bedrock, Secrets Manager, and RDS over SSL.
RUN apk --no-cache add ca-certificates

# The process has no reason to be root: it binds an unprivileged port and only
# ever reads its own binary.
RUN addgroup -g 65532 nonroot && \
    adduser -u 65532 -G nonroot -h /home/nonroot -D nonroot
WORKDIR /app

FROM runtime-base AS server
COPY --from=builder /out/server /app/server
USER nonroot:nonroot
EXPOSE 3000
ENTRYPOINT ["/app/server"]

# Local development only. Never deployed: no Terraform or CI path builds this
# stage, and it issues tokens without authenticating anyone.
FROM runtime-base AS devidp
COPY --from=builder /out/devidp /app/devidp
USER nonroot:nonroot
EXPOSE 9000
ENTRYPOINT ["/app/devidp"]
