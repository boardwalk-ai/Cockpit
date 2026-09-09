# syntax=docker/dockerfile:1
FROM golang:1.23-alpine AS build
RUN apk add --no-cache git
WORKDIR /src
COPY . .
RUN go mod tidy && CGO_ENABLED=0 go build -o /cockpit-go ./cmd/cockpit-go

FROM alpine:3.21
RUN apk add --no-cache ca-certificates
COPY --from=build /cockpit-go /usr/local/bin/cockpit-go
ENTRYPOINT ["cockpit-go"]
