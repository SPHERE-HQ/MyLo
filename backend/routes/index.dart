import 'package:dart_frog/dart_frog.dart';

Response onRequest(RequestContext context) {
  return Response.json(body: {
    'app': 'Mylo API by Sphere',
    'version': '1.0.0',
    'status': 'running',
    'docs': '/health',
  });
}
