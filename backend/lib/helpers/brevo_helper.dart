import "dart:convert";
import "dart:io";
import "dart:math";
import "package:http/http.dart" as http;

class BrevoHelper {
  static final _apiKey = Platform.environment["BREVO_API_KEY"] ?? "";
  static final _senderEmail = Platform.environment["BREVO_SENDER_EMAIL"] ?? "";
  static final _random = Random.secure();

  static String generateOtp() {
    return (_random.nextInt(900000) + 100000).toString();
  }

  static Future<bool> sendOtpEmail({
    required String toEmail,
    required String toName,
    required String otp,
  }) async {
    if (_apiKey.isEmpty || _senderEmail.isEmpty) {
      print("WARNING: BREVO_API_KEY atau BREVO_SENDER_EMAIL belum disetel");
      return false;
    }
    try {
      final response = await http.post(
        Uri.parse("https://api.brevo.com/v3/smtp/email"),
        headers: {
          "accept": "application/json",
          "api-key": _apiKey,
          "content-type": "application/json",
        },
        body: jsonEncode({
          "sender": {"name": "Mylo", "email": _senderEmail},
          "to": [{"email": toEmail, "name": toName}],
          "subject": "Kode Verifikasi Mylo: $otp",
          "htmlContent": """
<div style="font-family:Arial,sans-serif;max-width:480px;margin:0 auto;padding:24px;background:#fff;">
  <h2 style="color:#4F46E5;margin-bottom:8px;">Verifikasi Email Mylo</h2>
  <p style="color:#374151;">Hai <b>$toName</b>,</p>
  <p style="color:#374151;">Gunakan kode berikut untuk verifikasi email kamu:</p>
  <div style="background:#EEF2FF;border-radius:12px;padding:28px;text-align:center;margin:24px 0;">
    <span style="font-size:40px;font-weight:900;letter-spacing:10px;color:#4F46E5;">$otp</span>
  </div>
  <p style="color:#6B7280;font-size:13px;">Kode berlaku <b>10 menit</b>. Jangan bagikan ke siapapun.</p>
  <hr style="border:none;border-top:1px solid #E5E7EB;margin:20px 0;">
  <p style="color:#9CA3AF;font-size:12px;">Email ini dikirim otomatis oleh Mylo. Jika kamu tidak mendaftar, abaikan email ini.</p>
</div>
""",
        }),
      );
      return response.statusCode == 201;
    } catch (e) {
      print("Brevo error: $e");
      return false;
    }
  }
}

