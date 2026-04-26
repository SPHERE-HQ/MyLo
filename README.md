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
│   │   ├── app/                # Root widget, routing, design system
│   │   ├── core/               # API client + auth provider
│   │   ├── modules/            # Auth, Chat, Feed, Email, Community, Wallet
│   │   └── shared/             # Home shell + widget reusable
│   └── pubspec.yaml
│
└── backend/                    # Dart Frog Backend
    ├── routes/                 # Auth, Chat, Feed, Wallet, Notifications, Users
    ├── lib/                    # DB, middleware, helpers
    └── pubspec.yaml
```

---

## Download APK

Setiap push ke branch `main` otomatis membangun APK baru via GitHub Actions.

➡️ **Lihat semua release APK di tab [Releases](../../releases)**

Atau download dari tab **Actions → Build Mylo APK → Artifacts**

### Cara install di HP

1. **Kalau pernah install Mylo build lama, uninstall dulu** dari HP. Build baru pakai signature konsisten — sekali install build ini, update berikutnya bisa langsung tanpa uninstall lagi.
2. Download APK sesuai HP Anda. Kalau ragu, pakai **`app-release.apk`** (universal, pasti jalan di semua HP).
3. Buka **Pengaturan → Keamanan → Instal aplikasi tidak dikenal** → aktifkan untuk browser/file manager Anda.
4. Buka file APK → **Install**.

| File | Untuk Perangkat |
|------|----------------|
| `app-release.apk` | Universal — pasti jalan di HP apa pun (paling aman) |
| `app-arm64-v8a-release.apk` | HP modern 2019+ (ukuran lebih kecil) |
| `app-armeabi-v7a-release.apk` | HP lama / 32-bit |
| `app-x86_64-release.apk` | Emulator / Chromebook |

---

## Development

### Mobile

```bash
cd mobile
flutter pub get
flutter run
```

### Backend

```bash
cd backend
dart pub get
dart_frog dev
```

Konfigurasi environment di-handle via env file lokal (lihat tim untuk detail). **Jangan commit file env atau credential apa pun ke repo.**

### Test

```bash
cd mobile
flutter test
```

Test juga otomatis dijalankan di CI sebelum build APK — kalau test gagal, build dibatalkan dan laporan test diunggah sebagai artifact di GitHub Actions.

---

## API Endpoints (high level)

```
Auth          register, login, profil
Chat          conversations, messages
Feed          posts, stories, likes, comments
Wallet        balance, top up, transfer
Notifications inbox notifikasi
Users         search & profile
Health        health check
```

Detail endpoint, schema request/response, dan auth flow ada di dokumentasi internal tim — bukan di repo publik.

---

**Sphere HQ** — Mylo App | Flutter + Dart | 2025
