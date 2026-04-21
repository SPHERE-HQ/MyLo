FROM dart:stable

RUN apt-get update && apt-get install -y build-essential libssl-dev && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY backend/pubspec.yaml ./
RUN dart pub get

COPY backend/ .

EXPOSE 8080

CMD ["dart", "run", "bin/server.dart"]
