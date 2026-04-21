FROM dart:3.5.4

RUN apt-get update && apt-get install -y \
    build-essential \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY backend/pubspec.yaml ./
RUN dart pub get

COPY backend/ .

RUN dart pub global activate dart_frog_cli 1.3.0
RUN dart pub global run dart_frog_cli:dart_frog build

EXPOSE 8080

CMD ["dart", "run", "build/bin/server.dart"]
