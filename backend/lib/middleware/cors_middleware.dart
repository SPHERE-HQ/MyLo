import "package:shelf/shelf.dart";

Middleware corsMiddleware() {
  return (Handler handler) {
    return (Request request) async {
      if (request.method == "OPTIONS") {
        return Response.ok("", headers: _corsHeaders);
      }
      final response = await handler(request);
      return response.change(headers: _corsHeaders);
    };
  };
}

const _corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Authorization, Content-Type",
};
