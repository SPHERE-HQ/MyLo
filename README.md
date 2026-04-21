# Mylo — Super App by Sphere

  > *"Everything in your Sphere"*

  Mylo adalah super app all-in-one berbasis **Flutter + Dart** — chat, feed sosial, email, komunitas, e-wallet, notifikasi, dan storage dalam satu aplikasi.

  ---

  ## Tech Stack

  | Layer | Teknologi |
  |-------|-----------|
  | **Mobile App** | Flutter + Dart |
  | **State Management** | Riverpod |
  | **Navigation** | GoRouter |
  | **HTTP Client** | Dio |
  | **Backend** | Dart Frog |
  | **Database** | PostgreSQL |
  | **Auth** | JWT (dart_jsonwebtoken + bcrypt) |
  | **Hosting** | Railway |
  | **CI/CD** | GitHub Actions — Build APK otomatis |

  ---

  ## Struktur Repo

  ```
  MyLo/
  ├── .github/
  │   └── workflows/
  │       └── build-apk.yml       # Build APK otomatis setiap push ke main
  │
  ├── mobile/                     # Flutter App
  │   ├── lib/
  │   │   ├── main.dart
  │   │   ├── app/
  │   │   │   ├── app.dart        # Root widget
  │   │   │   ├── routes.dart     # GoRouter — semua navigasi
  │   │   │   └── theme.dart      # Design system (warna, spacing, radius)
  │   │   ├── core/
  │   │   │   ├── api/            # Dio HTTP client
  │   │   │   └── auth/           # Auth provider + token manager
  │   │   ├── modules/
  │   │   │   ├── auth/           # Login, Register, Splash, Onboarding
  │   │   │   ├── chat/           # Chat list + Chat room + WebSocket
  │   │   │   ├── feed/           # Feed, Explore, Stories, Reel
  │   │   │   ├── email/          # Inbox, Detail, Compose
  │   │   │   ├── community/      # Server list + Channel + Messages
  │   │   │   └── wallet/         # Saldo, Top up, Transfer
  │   │   └── shared/
  │   │       ├── screens/        # Home shell + Bottom nav
  │   │       └── widgets/        # MButton, MAvatar, MLoadingSkeleton, dll
  │   └── pubspec.yaml
  │
  └── backend/                    # Dart Frog Backend
      ├── routes/
      │   ├── index.dart
      │   ├── health.dart
      │   ├── auth/               # register, login, me
      │   ├── chat/               # conversations, messages
      │   ├── feed/               # posts, stories, likes, comments
      │   ├── wallet/             # balance, topup, transfer
      │   ├── notifications/
      │   └── users/              # search, profile
      ├── lib/
      │   ├── db/
      │   │   ├── database.dart   # PostgreSQL connection
      │   │   └── schema.sql      # DDL — jalankan sekali untuk init DB
      │   ├── middleware/
      │   │   └── auth_middleware.dart  # JWT verification
      │   └── helpers/
      │       ├── jwt_helper.dart
      │       └── response_helper.dart
      └── pubspec.yaml
  ```

  ---

  ## Download APK

  Setiap push ke branch `main` akan otomatis membangun APK baru via GitHub Actions.

  ➡️ **[Lihat semua release APK](https://github.com/SPHERE-HQ/MyLo/releases)**

  Atau download dari tab **Actions → Build Mylo APK → Artifacts**

  ---

  ## Setup Backend di Railway

  ### 1. Environment Variables

  ```
  DATABASE_URL  = postgresql://...railway...
  JWT_SECRET    = <string acak panjang, min 64 karakter>
  PORT          = 8080
  ```

  ### 2. Build Command

  ```bash
  dart pub get
  ```

  ### 3. Start Command

  ```bash
  dart run bin/server.dart
  ```

  ### 4. Init Database (sekali saja)

  Jalankan isi file `backend/lib/db/schema.sql` di Railway PostgreSQL console.

  ---

  ## API Endpoints

  ```
  POST  /auth/register        Daftar akun
  POST  /auth/login           Login → JWT token
  GET   /auth/me              Profil aktif
  PUT   /auth/me              Update profil

  GET   /chat/conversations   List percakapan
  POST  /chat/conversations   Buat percakapan
  GET   /chat/conversations/:id/messages  Ambil pesan
  POST  /chat/conversations/:id/messages  Kirim pesan

  GET   /feed/posts           Timeline
  POST  /feed/posts           Buat post
  POST  /feed/posts/:id/like  Like/unlike

  GET   /wallet               Info saldo
  POST  /wallet/topup         Top up
  POST  /wallet/transfer      Transfer ke user lain

  GET   /notifications        Semua notifikasi
  GET   /users/search?q=      Cari user
  GET   /health               Health check
  ```

  ---

  **Sphere HQ** — Mylo App | Flutter + Dart | 2025
  