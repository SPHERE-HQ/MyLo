# Mylo — Super App by Sphere

  > *"Everything in your Sphere"*

  Mylo adalah super app all-in-one yang menggabungkan chat, feed sosial, email, komunitas, e-wallet, dan lebih banyak lagi dalam satu platform.

  ---

  ## Modul Aplikasi

  | Modul | Deskripsi |
  |-------|-----------|
  | **Chat & Messaging** | Percakapan privat & grup, story, voice note |
  | **Feed Sosial** | Post, reels, like, komentar, story |
  | **Email Client** | Inbox, kirim, draft, label, folder |
  | **Komunitas** | Server & channel berbasis teks (seperti Discord) |
  | **E-Wallet** | Saldo, top up, transfer antar pengguna |
  | **Notifikasi** | Notifikasi terpusat dari semua modul |
  | **Cloud Storage** | Manajemen file dari semua modul |

  ---

  ## Tech Stack

  - **Frontend/Mobile:** Flutter (planned)
  - **Backend:** Node.js + Express 5 + TypeScript
  - **Database:** PostgreSQL + Drizzle ORM
  - **Validation:** Zod
  - **Auth:** JWT (jsonwebtoken + bcryptjs)
  - **Hosting:** Railway
  - **Monorepo:** pnpm workspaces

  ---

  ## Struktur Repo

  ```
  MyLo/
  ├── artifacts/
  │   └── api-server/          # Express API server
  │       └── src/
  │           ├── routes/       # Auth, Chat, Feed, Email, Community, Wallet, dll
  │           ├── lib/          # Auth helpers (JWT, bcrypt)
  │           └── middlewares/  # JWT authentication middleware
  ├── lib/
  │   ├── db/                  # Drizzle ORM schema & connection
  │   │   └── src/schema/      # Users, Sessions, Chat, Feed, Email, Wallet, dll
  │   ├── api-spec/            # OpenAPI specification
  │   ├── api-zod/             # Zod schemas (generated)
  │   └── api-client-react/    # React Query hooks (generated)
  ```

  ---

  ## API Endpoints

  ### Auth `/api/auth`
  ```
  POST   /register       Daftar akun baru
  POST   /login          Login, return JWT token
  POST   /logout         Logout
  GET    /me             Profil pengguna aktif
  PUT    /me             Update profil
  ```

  ### Chat `/api/chat`
  ```
  GET    /conversations                      List percakapan
  POST   /conversations                      Buat percakapan baru
  GET    /conversations/:id/messages         List pesan
  POST   /conversations/:id/messages         Kirim pesan
  DELETE /messages/:id                       Hapus pesan
  ```

  ### Feed `/api/feed`
  ```
  GET    /              Timeline
  POST   /posts         Buat post
  GET    /posts/:id     Detail post
  POST   /posts/:id/like      Like/unlike
  POST   /posts/:id/comments  Komentar
  POST   /follow/:userId      Follow/unfollow
  GET    /stories             Stories user
  POST   /stories             Buat story
  GET    /explore             Explore
  ```

  ### Email `/api/email`
  ```
  GET    /              List email (per folder)
  GET    /:id           Baca email
  POST   /              Kirim email
  PUT    /:id           Update (star, folder, read)
  DELETE /:id           Hapus (ke trash)
  ```

  ### Komunitas `/api/community`
  ```
  GET    /servers                    List server publik
  POST   /servers                    Buat server
  GET    /servers/:id                Detail + channels
  POST   /servers/:id/channels       Buat channel
  GET    /channels/:id/messages      List pesan channel
  POST   /channels/:id/messages      Kirim pesan
  ```

  ### Wallet `/api/wallet`
  ```
  GET    /              Info saldo
  GET    /transactions  Riwayat transaksi
  POST   /topup         Top up saldo
  POST   /transfer      Transfer ke user lain
  POST   /pin           Set PIN wallet
  ```

  ### Lainnya
  ```
  GET/PUT  /api/notifications          Notifikasi
  GET/POST /api/storage/files          File management
  GET      /api/users/search?q=        Cari user
  GET      /api/users/:id              Profil user
  GET      /api/healthz                Health check
  ```

  ---

  ## Setup Railway

  ### Environment Variables
  ```
  DATABASE_URL=postgresql://...
  JWT_SECRET=<random-string-panjang>
  SESSION_SECRET=<random-string-panjang>
  PORT=3000
  NODE_ENV=production
  ```

  ### Build Command
  ```bash
  pnpm install && pnpm --filter @workspace/api-server run build
  ```

  ### Start Command
  ```bash
  node artifacts/api-server/dist/index.mjs
  ```

  ---

  ## Database Migration

  Setelah deploy, jalankan sekali untuk membuat semua tabel:
  ```bash
  DATABASE_URL=<your-url> pnpm --filter @workspace/db run push
  ```

  ---

  ## Development Lokal

  ```bash
  # Install dependencies
  pnpm install

  # Jalankan API server (development)
  DATABASE_URL=... JWT_SECRET=... PORT=3000 pnpm --filter @workspace/api-server run dev
  ```

  ---

  **Sphere HQ** — Mylo App
  