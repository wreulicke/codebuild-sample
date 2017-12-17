FROM openjdk:8-jdk-alpine

RUN apk add --no-cache \
        openssh \
        git
