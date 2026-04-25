import "dart:async";
import "package:shelf/shelf.dart";

class _Bucket {
  int count = 0;
  DateTime windowStart = DateTime.now();
}

final Map<String, _Bucket> _buckets = {};

Middleware rateLimitMiddleware({int maxPerMinute = 120, int authMaxPerMinute = 10}) {
  return (Handler inner) {
    return (Request req) async {
      final ip = (req.headers["x-forwarded-for"] ?? "unknown").split(",").first.trim();
      final isAuth = req.url.path.startsWith("auth/");
      final key = "$ip:${isAuth ? "auth" : "general"}";
      final limit = isAuth ? authMaxPerMinute : maxPerMinute;
      final bucket = _buckets.putIfAbsent(key, () => _Bucket());
      final now = DateTime.now();
      if (now.difference(bucket.windowStart).inSeconds >= 60) {
        bucket.windowStart = now;
        bucket.count = 0;
      }
      bucket.count++;
      if (bucket.count > limit) {
        return Response(429,
            headers: {"content-type": "application/json", "retry-after": "60"},
            body: '{"error":"Too many requests, slow down"}');
      }
      return inner(req);
    };
  };
}
