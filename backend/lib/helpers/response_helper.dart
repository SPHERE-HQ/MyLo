import "dart:convert";
import "package:shelf/shelf.dart";

Response jsonResponse(dynamic data, [int statusCode = 200]) {
  return Response(
    statusCode,
    body: jsonEncode(data),
    headers: {"Content-Type": "application/json"},
  );
}

Response ok(dynamic data) => jsonResponse(data, 200);
Response created(dynamic data) => jsonResponse(data, 201);
Response badRequest(String message) => jsonResponse({"error": message}, 400);
Response unauthorized([String message = "Unauthorized"]) => jsonResponse({"error": message}, 401);
Response notFound(String message) => jsonResponse({"error": message}, 404);
Response conflict(String message) => jsonResponse({"error": message}, 409);
Response serverError([String message = "Internal server error"]) => jsonResponse({"error": message}, 500);
