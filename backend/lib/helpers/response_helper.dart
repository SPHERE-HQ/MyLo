import 'package:dart_frog/dart_frog.dart';

Response ok(dynamic data) =>
    Response.json(body: data, statusCode: 200);

Response created(dynamic data) =>
    Response.json(body: data, statusCode: 201);

Response badRequest(String message) =>
    Response.json(body: {'error': message}, statusCode: 400);

Response unauthorized() =>
    Response.json(body: {'error': 'Unauthorized'}, statusCode: 401);

Response notFound(String message) =>
    Response.json(body: {'error': message}, statusCode: 404);

Response conflict(String message) =>
    Response.json(body: {'error': message}, statusCode: 409);

Response serverError() =>
    Response.json(body: {'error': 'Internal server error'}, statusCode: 500);
