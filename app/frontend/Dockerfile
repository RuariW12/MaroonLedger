# Two runnable targets:
#   dev        - CRA dev server with hot reload, used by docker-compose
#   production - the built bundle served by nginx, which mirrors how
#                CloudFront serves it from S3 in AWS
#
# Building the production target locally is the only way to catch problems that
# exist solely in the production bundle: minification issues, a missing
# REACT_APP_* variable, or SPA routing that works under the dev server's
# catch-all but not under a real web server.

FROM node:22-alpine AS deps
WORKDIR /app
# npm ci installs exactly what the lockfile pins and fails if the two have
# drifted, which is what makes the image reproducible.
COPY package.json package-lock.json ./
RUN npm ci

FROM node:22-alpine AS dev
WORKDIR /app
ENV NODE_ENV=development
# Without this the dev server binds to loopback inside the container and is
# unreachable from the host.
ENV HOST=0.0.0.0
COPY --from=deps /app/node_modules ./node_modules
COPY . .
EXPOSE 3001
CMD ["npm", "start"]

FROM node:22-alpine AS build
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# REACT_APP_* values are baked into the bundle at build time, not read at
# runtime -- a React app is static files with no server to read an environment.
# Changing any of these requires rebuilding the image.
#
# None of them are secrets. The Cognito client ID is public by design: it
# identifies the app and ships in the bundle either way. Never pass an actual
# secret here; it would be readable in the shipped JavaScript.
ARG REACT_APP_AUTH_MODE=dev
ARG REACT_APP_DEV_IDP_URL=http://localhost:9000
ARG REACT_APP_COGNITO_DOMAIN=
ARG REACT_APP_COGNITO_CLIENT_ID=
ARG REACT_APP_REDIRECT_URI=

ENV REACT_APP_AUTH_MODE=$REACT_APP_AUTH_MODE \
    REACT_APP_DEV_IDP_URL=$REACT_APP_DEV_IDP_URL \
    REACT_APP_COGNITO_DOMAIN=$REACT_APP_COGNITO_DOMAIN \
    REACT_APP_COGNITO_CLIENT_ID=$REACT_APP_COGNITO_CLIENT_ID \
    REACT_APP_REDIRECT_URI=$REACT_APP_REDIRECT_URI

# Treat warnings as errors, so a lint warning fails the build here rather than
# shipping.
ENV CI=true
RUN npm run build

FROM nginx:1.27-alpine AS production
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build /usr/share/nginx/html
EXPOSE 80
