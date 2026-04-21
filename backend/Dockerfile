FROM dart:3.3.0

WORKDIR /app

COPY pubspec.yaml pubspec.lock* ./
RUN dart pub get

COPY . .

RUN dart pub global activate dart_frog_cli

RUN dart pub global run dart_frog_cli:dart_frog build

EXPOSE 8080

CMD ["dart", "run", "build/bin/server.dart"]
