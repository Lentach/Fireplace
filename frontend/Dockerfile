# Stage 1: Build Flutter web app
FROM ghcr.io/cirruslabs/flutter:latest AS build

WORKDIR /app

# Copy dependency files first for better layer caching
COPY pubspec.* ./
RUN flutter pub get && \
    flutter pub cache clean --force

# Copy source code
COPY . .

# Build for web
RUN flutter build web --dart-define=BASE_URL= --release

# Stage 2: Serve with nginx
FROM nginx:alpine

COPY --from=build /app/build/web /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
