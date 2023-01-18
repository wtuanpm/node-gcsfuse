FROM golang:1.16.0-alpine AS gcsfuse
RUN apk add --no-cache git
ENV GOPATH /go
RUN go env -w GO111MODULE=off
RUN go get -u github.com/googlecloudplatform/gcsfuse

FROM node:alpine AS development

WORKDIR /usr/src/app

COPY package*.json ./

RUN npm install

COPY . . 

RUN npm run build

FROM node:alpine as production

# Install fuse (requirement)
RUN apk add --no-cache ca-certificates fuse && rm -rf /tmp/*
RUN apk add --no-cache ca-certificates bash && rm -rf /tmp/*


ARG NODE_ENV=production
ENV NODE_ENV=${NODE_ENV}
WORKDIR /usr/src/app

COPY package*.json ./
RUN npm install --only=prod
COPY . .
COPY --from=development /usr/src/app/dist ./dist


COPY service-account.json /etc/gcp/sa_credentials.json
ENV GOOGLE_APPLICATION_CREDENTIALS="/etc/gcp/sa_credentials.json"

# Credential file to use and write,
# note that this is ignored if the credential file already exists
ENV GOOGLE_APPLICATION_CREDENTIALS_JSON=""


# Mount point for the gcs file system
ENV GCSFUSE_MOUNT="/usr/share/bucket-data"

# Bucket name to mount
ENV GCSFUSE_BUCKET="ride-hailing-dev"

# GCSFUSE arguments to use
# See : https://github.com/GoogleCloudPlatform/gcsfuse


RUN apk add --no-cache ca-certificates fuse

COPY --from=gcsfuse /go/bin/gcsfuse /usr/local/bin
RUN mkdir -p /usr/share/bucket-data

#
# Setup any of the GCS credential json, if found
#
RUN mkdir -p /entrypoint/ && \
    echo '#!/bin/bash' > /entrypoint/gcsfuse.sh && \
    echo ''                                                              >> /entrypoint/gcsfuse.sh && \
    echo '# Configuration checks'                                        >> /entrypoint/gcsfuse.sh && \
    echo 'if [ -z "${GCSFUSE_BUCKET}" ]; then'                           >> /entrypoint/gcsfuse.sh && \
    echo '    echo "Error: GCSFUSE_BUCKET is not specified"'             >> /entrypoint/gcsfuse.sh && \
    echo '    exit 128'                                                  >> /entrypoint/gcsfuse.sh && \
    echo 'fi'                                                            >> /entrypoint/gcsfuse.sh && \
    echo ''                                                              >> /entrypoint/gcsfuse.sh && \
    echo '# Write auth file if it does not exist'                        >> /entrypoint/gcsfuse.sh && \
    echo 'if [ ! -f "${GOOGLE_APPLICATION_CREDENTIALS}" ]; then'         >> /entrypoint/gcsfuse.sh && \
    echo '    if [ -z "${GOOGLE_APPLICATION_CREDENTIALS_JSON}" ]; then'  >> /entrypoint/gcsfuse.sh && \
    echo '        echo "Error: Missing GOOGLE_APPLICATION_CREDENTIALS_JSON or ${GOOGLE_APPLICATION_CREDENTIALS} not provided"'  >> /entrypoint/gcsfuse.sh && \
    echo '        exit 128'                                              >> /entrypoint/gcsfuse.sh && \
    echo '    fi'                                                        >> /entrypoint/gcsfuse.sh && \
    echo '    echo "${GOOGLE_APPLICATION_CREDENTIALS_JSON}" > ${GOOGLE_APPLICATION_CREDENTIALS}'  >> /entrypoint/gcsfuse.sh && \
    echo 'fi'                                                            >> /entrypoint/gcsfuse.sh && \
    echo ''                                                              >> /entrypoint/gcsfuse.sh && \
    echo 'echo "==> [picoded/gcsfuse] : Mounting GCS Filesystem"'        >> /entrypoint/gcsfuse.sh && \
    echo 'mkdir -p ${GCSFUSE_MOUNT}'                                     >> /entrypoint/gcsfuse.sh && \
    echo 'gcsfuse ${GCSFUSE_BUCKET} ${GCSFUSE_MOUNT}'      >> /entrypoint/gcsfuse.sh && \
    echo ''                                                              >> /entrypoint/gcsfuse.sh && \
    echo 'echo "==> [picoded/gcsfuse] : Entrypoint Chain"'               >> /entrypoint/gcsfuse.sh && \
    echo 'exec "$@"'                                                     >> /entrypoint/gcsfuse.sh && \
    chmod +x /entrypoint/gcsfuse.sh;
ENTRYPOINT [ "/entrypoint/gcsfuse.sh" ]

CMD ["node", "dist/main"]

