# Build once, produce two binaries. `server` is the production target; `devidp`
# is a local-only identity provider that issues tokens without authenticating
# anyone.
#
# `server` is deliberately the LAST stage. `docker build .` with no --target
# builds whichever stage comes last, so ordering is what decides the default,
# and the default has to be the safe one. With devidp last, a plain build
# silently produces an image whose entrypoint hands out tokens to anyone --
# which is exactly what happened once.
# --platform=$BUILDPLATFORM pins the builder to the *native* architecture, and
# GOARCH comes from the target instead. Go cross-compiles directly, so an
# amd64 image builds on an arm64 machine at native speed. Without this, Docker
# runs the whole toolchain under QEMU emulation to match the target, which
# turns a sub-minute Go build into many minutes.
FROM --platform=$BUILDPLATFORM golang:1.25-alpine AS builder
ARG TARGETOS
ARG TARGETARCH
WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .
# CGO_ENABLED=0 produces a static binary, which is what allows the runtime
# stage to carry nothing but the binary and CA certificates.
RUN CGO_ENABLED=0 GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH:-amd64} go build -trimpath -ldflags="-s -w" -o /out/server ./cmd/server
RUN CGO_ENABLED=0 GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH:-amd64} go build -trimpath -ldflags="-s -w" -o /out/devidp ./cmd/devidp

# Pinned to a minor release rather than :latest, so a base image change is a
# reviewable commit. 3.19 was carried until Trivy failed the build on
# CVE-2026-40200 in musl, which that line still ships unpatched; 3.22 is on
# musl 1.2.5 and clears it.
FROM alpine:3.22 AS runtime-base
# TLS roots are required to reach Bedrock, Secrets Manager, and RDS over SSL.
RUN apk --no-cache add ca-certificates

# The process has no reason to be root: it binds an unprivileged port and only
# ever reads its own binary.
RUN addgroup -g 65532 nonroot && \
    adduser -u 65532 -G nonroot -h /home/nonroot -D nonroot
WORKDIR /app

# Local development only, and reached solely by docker-compose naming this
# stage explicitly. Kept above `server` so it can never be the default target.
FROM runtime-base AS devidp
COPY --from=builder /out/devidp /app/devidp
USER nonroot:nonroot
EXPOSE 9000
ENTRYPOINT ["/app/devidp"]

FROM runtime-base AS server
COPY --from=builder /out/server /app/server
USER nonroot:nonroot
EXPOSE 3000
ENTRYPOINT ["/app/server"]
