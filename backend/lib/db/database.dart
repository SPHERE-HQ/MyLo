import "dart:io";
import "package:postgres/postgres.dart";

// Re-export Sql so files that import this database.dart can use Sql.named(...)
// without needing a direct import on package:postgres.
export "package:postgres/postgres.dart" show Sql;

Connection? _db;
bool _dbAvailable = false;

Future<Connection> getDb() async {
  if (_db == null || !_dbAvailable) {
    throw StateError("Database tidak tersedia. Pastikan DATABASE_URL di-set.");
  }
  return _db!;
}

Future<void> initDb() async {
  final url = Platform.environment["DATABASE_URL"] ?? "";
  if (url.isEmpty) {
    print("WARNING: DATABASE_URL tidak di-set — server berjalan tanpa database.");
    _dbAvailable = false;
    return;
  }
  try {
    final uri = Uri.parse(url);
    final parts = uri.userInfo.split(":");
    _db = await Connection.open(
      Endpoint(
        host: uri.host,
        port: uri.port == 0 ? 5432 : uri.port,
        database: uri.pathSegments.first,
        username: parts[0],
        password: parts.length > 1 ? parts[1] : "",
      ),
      settings: const ConnectionSettings(sslMode: SslMode.require),
    );
    _dbAvailable = true;
    print("Database connected");
    await _runMigrations();
  } catch (e) {
    print("ERROR: Gagal connect ke database: $e");
    _dbAvailable = false;
  }
}

// Helper: idempotently rename a legacy table to the new name expected by the
// current code base. Safe to run on every boot.
Future<void> _renameIfExists(String oldName, String newName) async {
  await _db!.execute("""
    DO \$\$
    BEGIN
      IF EXISTS (SELECT 1 FROM information_schema.tables
                 WHERE table_schema = 'public' AND table_name = '$oldName')
         AND NOT EXISTS (SELECT 1 FROM information_schema.tables
                         WHERE table_schema = 'public' AND table_name = '$newName')
      THEN
        EXECUTE 'ALTER TABLE public.$oldName RENAME TO $newName';
      END IF;
    END
    \$\$;
  """);
}

Future<void> _runMigrations() async {
  print("Running migrations...");

  // ─── LEGACY RENAMES (run BEFORE any CREATE TABLE that references the new
  //     names, so existing data is preserved instead of being shadowed by an
  //     empty table). ─────────────────────────────────────────────────────
  await _renameIfExists("posts", "feed_posts");
  await _renameIfExists("conversations", "chat_conversations");
  await _renameIfExists("conversation_members", "chat_members");
  await _renameIfExists("messages", "chat_messages");

  // ─── USERS ───────────────────────────────────────────────
  await _db!.execute("""
    CREATE TABLE IF NOT EXISTS users (
      id UUID PRIMARY KEY,
      username VARCHAR(50) UNIQUE NOT NULL,
      email VARCHAR(255) UNIQUE NOT NULL,
      password_hash TEXT,
      display_name VARCHAR(100),
      avatar_url TEXT,
      bio TEXT,
      phone VARCHAR(20),
      is_verified BOOLEAN DEFAULT FALSE,
      two_factor_enabled BOOLEAN DEFAULT FALSE,
      google_sub TEXT,
      created_at TIMESTAMPTZ DEFAULT NOW(),
      updated_at TIMESTAMPTZ DEFAULT NOW()
    )
  """);
  await _db!.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS two_factor_enabled BOOLEAN DEFAULT FALSE");
  await _db!.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS google_sub TEXT");
  await _db!.execute("ALTER TABLE users ALTER COLUMN password_hash DROP NOT NULL");
  await _db!.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_users_google_sub ON users(google_sub) WHERE google_sub IS NOT NULL");

  // ─── SESSIONS ────────────────────────────────────────────
  await _db!.execute("""
    CREATE TABLE IF NOT EXISTS sessions (
      id UUID PRIMARY KEY,
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      token TEXT NOT NULL,
      expires_at TIMESTAMPTZ NOT NULL,
      created_at TIMESTAMPTZ DEFAULT NOW()
    )
  """);

  // ─── EMAIL VERIFICATIONS ─────────────────────────────────
  await _db!.execute("""
    CREATE TABLE IF NOT EXISTS email_verifications (
      id UUID PRIMARY KEY,
      email VARCHAR(255) NOT NULL,
      code VARCHAR(6) NOT NULL,
      expires_at TIMESTAMPTZ NOT NULL,
      used BOOLEAN DEFAULT FALSE,
      created_at TIMESTAMPTZ DEFAULT NOW()
    )
  """);

  // ─── FOLLOWS ─────────────────────────────────────────────
  await _db!.execute("""
    CREATE TABLE IF NOT EXISTS follows (
      id UUID PRIMARY KEY,
      follower_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      following_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      created_at TIMESTAMPTZ DEFAULT NOW(),
      UNIQUE(follower_id, following_id)
    )
  """);

  // ─── FEED POSTS (renamed from "posts") ───────────────────
  await _db!.execute("""
    CREATE TABLE IF NOT EXISTS feed_posts (
      id UUID PRIMARY KEY,
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      caption TEXT,
      content TEXT,
      media_urls JSONB DEFAULT '[]',
      image_url TEXT,
      type VARCHAR(20) DEFAULT 'post',
      likes_count INT DEFAULT 0,
      comments_count INT DEFAULT 0,
      is_archived BOOLEAN DEFAULT FALSE,
      created_at TIMESTAMPTZ DEFAULT NOW(),
      updated_at TIMESTAMPTZ DEFAULT NOW()
    )
  """);
  await _db!.execute("ALTER TABLE feed_posts ADD COLUMN IF NOT EXISTS caption TEXT");
  await _db!.execute("ALTER TABLE feed_posts ADD COLUMN IF NOT EXISTS media_urls JSONB DEFAULT '[]'");
  await _db!.execute("ALTER TABLE feed_posts ADD COLUMN IF NOT EXISTS type VARCHAR(20) DEFAULT 'post'");
  await _db!.execute("ALTER TABLE feed_posts ADD COLUMN IF NOT EXISTS likes_count INT DEFAULT 0");
  await _db!.execute("ALTER TABLE feed_posts ADD COLUMN IF NOT EXISTS comments_count INT DEFAULT 0");
  await _db!.execute("ALTER TABLE feed_posts ADD COLUMN IF NOT EXISTS is_archived BOOLEAN DEFAULT FALSE");

  // ─── POST LIKES ──────────────────────────────────────────
  await _db!.execute("""
    CREATE TABLE IF NOT EXISTS post_likes (
      id UUID PRIMARY KEY,
      post_id UUID NOT NULL REFERENCES feed_posts(id) ON DELETE CASCADE,
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      created_at TIMESTAMPTZ DEFAULT NOW(),
      UNIQUE(post_id, user_id)
    )
  """);

  // ─── POST COMMENTS ───────────────────────────────────────
  await _db!.execute("""
    CREATE TABLE IF NOT EXISTS post_comments (
      id UUID PRIMARY KEY,
      post_id UUID NOT NULL REFERENCES feed_posts(id) ON DELETE CASCADE,
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      parent_id UUID REFERENCES post_comments(id) ON DELETE CASCADE,
      content TEXT NOT NULL,
      created_at TIMESTAMPTZ DEFAULT NOW()
    )
  """);

  // ─── STORIES ─────────────────────────────────────────────
  await _db!.execute("""
    CREATE TABLE IF NOT EXISTS stories (
      id UUID PRIMARY KEY,
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      type VARCHAR(20) DEFAULT 'image',
      media_url TEXT NOT NULL,
      caption TEXT,
      views JSONB DEFAULT '[]',
      expires_at TIMESTAMPTZ NOT NULL,
      created_at TIMESTAMPTZ DEFAULT NOW()
    )
  """);

  // ─── CHAT CONVERSATIONS (renamed from "conversations") ───
  await _db!.execute("""
    CREATE TABLE IF NOT EXISTS chat_conversations (
      id UUID PRIMARY KEY,
      type VARCHAR(20) DEFAULT 'private',
      name VARCHAR(100),
      avatar_url TEXT,
      created_by UUID REFERENCES users(id) ON DELETE SET NULL,
      created_at TIMESTAMPTZ DEFAULT NOW()
    )
  """);
  await _db!.execute("ALTER TABLE chat_conversations ADD COLUMN IF NOT EXISTS type VARCHAR(20) DEFAULT 'private'");
  await _db!.execute("ALTER TABLE chat_conversations ADD COLUMN IF NOT EXISTS name VARCHAR(100)");
  await _db!.execute("ALTER TABLE chat_conversations ADD COLUMN IF NOT EXISTS avatar_url TEXT");
  await _db!.execute("ALTER TABLE chat_conversations ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES users(id) ON DELETE SET NULL");

  // ─── CHAT MEMBERS (renamed from "conversation_members") ──
  await _db!.execute("""
    CREATE TABLE IF NOT EXISTS chat_members (
      conversation_id UUID NOT NULL REFERENCES chat_conversations(id) ON DELETE CASCADE,
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      role VARCHAR(20) DEFAULT 'member',
      joined_at TIMESTAMPTZ DEFAULT NOW(),
      PRIMARY KEY (conversation_id, user_id)
    )
  """);
  await _db!.execute("ALTER TABLE chat_members ADD COLUMN IF NOT EXISTS role VARCHAR(20) DEFAULT 'member'");
  await _db!.execute("ALTER TABLE chat_members ADD COLUMN IF NOT EXISTS archived BOOLEAN DEFAULT FALSE");

  // ─── STICKERS (custom user stickers) ─────────────────────
  await _db!.execute("""
    CREATE TABLE IF NOT EXISTS stickers (
      id UUID PRIMARY KEY,
      owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      name TEXT NOT NULL,
      image_url TEXT NOT NULL,
      mime_type TEXT,
      is_favorite BOOLEAN DEFAULT FALSE,
      created_at TIMESTAMPTZ DEFAULT NOW()
    )
  """);
  await _db!.execute("CREATE INDEX IF NOT EXISTS stickers_owner_idx ON stickers(owner_id, is_favorite DESC, created_at DESC)");

  // ─── CHAT MESSAGES (renamed from "messages") ─────────────
  await _db!.execute("""
    CREATE TABLE IF NOT EXISTS chat_messages (
      id UUID PRIMARY KEY,
      conversation_id UUID NOT NULL REFERENCES chat_conversations(id) ON DELETE CASCADE,
      sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      type VARCHAR(20) DEFAULT 'text',
      content TEXT,
      media_url TEXT,
      reply_to_id UUID REFERENCES chat_messages(id) ON DELETE SET NULL,
      is_deleted BOOLEAN DEFAULT FALSE,
      read_by JSONB DEFAULT '[]',
      created_at TIMESTAMPTZ DEFAULT NOW()
    )
  """);
  await _db!.execute("ALTER TABLE chat_messages ADD COLUMN IF NOT EXISTS type VARCHAR(20) DEFAULT 'text'");
  await _db!.execute("ALTER TABLE chat_messages ADD COLUMN IF NOT EXISTS media_url TEXT");
  await _db!.execute("ALTER TABLE chat_messages ADD COLUMN IF NOT EXISTS reply_to_id UUID REFERENCES chat_messages(id) ON DELETE SET NULL");
  await _db!.execute("ALTER TABLE chat_messages ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN DEFAULT FALSE");
  await _db!.execute("ALTER TABLE chat_messages ADD COLUMN IF NOT EXISTS read_by JSONB DEFAULT '[]'");
  // Pesan stiker / media murni tidak punya teks → kolom content harus boleh NULL.
  // Drop legacy NOT NULL kalau pernah diset dari skema lama `messages`.
  await _db!.execute("ALTER TABLE chat_messages ALTER COLUMN content DROP NOT NULL");

  // Backwards-compat views: a few legacy queries still reference the old
  // names. Expose them as updatable views over the renamed tables.
  await _db!.execute("CREATE OR REPLACE VIEW posts AS SELECT * FROM feed_posts");
  await _db!.execute("CREATE OR REPLACE VIEW conversations AS SELECT * FROM chat_conversations");
  await _db!.execute("CREATE OR REPLACE VIEW conversation_members AS SELECT * FROM chat_members");
  await _db!.execute("CREATE OR REPLACE VIEW messages AS SELECT * FROM chat_messages");

  // ─── WALLETS ─────────────────────────────────────────────
  await _db!.execute("""
    CREATE TABLE IF NOT EXISTS wallets (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id UUID UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      balance NUMERIC(15,2) DEFAULT 0.00,
      currency VARCHAR(10) DEFAULT 'IDR',
      is_active BOOLEAN DEFAULT TRUE,
      pin_hash TEXT,
      updated_at TIMESTAMPTZ DEFAULT NOW()
    )
  """);
  await _db!.execute("ALTER TABLE wallets ADD COLUMN IF NOT EXISTS id UUID DEFAULT gen_random_uuid()");
  await _db!.execute("ALTER TABLE wallets ADD COLUMN IF NOT EXISTS currency VARCHAR(10) DEFAULT 'IDR'");
  await _db!.execute("ALTER TABLE wallets ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT TRUE");
  await _db!.execute("ALTER TABLE wallets ADD COLUMN IF NOT EXISTS pin_hash TEXT");

  // ─── WALLET TRANSACTIONS ─────────────────────────────────
  await _db!.execute("""
    CREATE TABLE IF NOT EXISTS wallet_transactions (
      id UUID PRIMARY KEY,
      wallet_id UUID NOT NULL REFERENCES wallets(user_id) ON DELETE CASCADE,
      type VARCHAR(30) NOT NULL,
      amount NUMERIC(15,2) NOT NULL,
      fee NUMERIC(15,2) DEFAULT 0.00,
      description TEXT,
      reference_id TEXT,
      counterparty_id UUID REFERENCES users(id) ON DELETE SET NULL,
      status VARCHAR(20) DEFAULT 'pending',
      metadata JSONB DEFAULT '{}',
      created_at TIMESTAMPTZ DEFAULT NOW()
    )
  """);

  // ─── NOTIFICATIONS ───────────────────────────────────────
  await _db!.execute("""
    CREATE TABLE IF NOT EXISTS notifications (
      id UUID PRIMARY KEY,
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      type VARCHAR(50),
      title TEXT,
      body TEXT,
      data JSONB DEFAULT '{}',
      is_read BOOLEAN DEFAULT FALSE,
      created_at TIMESTAMPTZ DEFAULT NOW()
    )
  """);
  await _db!.execute("ALTER TABLE notifications ADD COLUMN IF NOT EXISTS data JSONB DEFAULT '{}'");

  // ─── USER FILES ──────────────────────────────────────────
  await _db!.execute("""
    CREATE TABLE IF NOT EXISTS user_files (
      id UUID PRIMARY KEY,
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      name TEXT NOT NULL,
      url TEXT NOT NULL,
      size BIGINT,
      mime_type TEXT,
      source VARCHAR(30) DEFAULT 'manual',
      created_at TIMESTAMPTZ DEFAULT NOW()
    )
  """);

  // ─── COMMUNITY SERVERS ───────────────────────────────────
  await _db!.execute("""
    CREATE TABLE IF NOT EXISTS community_servers (
      id UUID PRIMARY KEY,
      name VARCHAR(100) NOT NULL,
      description TEXT,
      icon_url TEXT,
      banner_url TEXT,
      owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      is_public BOOLEAN DEFAULT TRUE,
      invite_code VARCHAR(20) UNIQUE,
      created_at TIMESTAMPTZ DEFAULT NOW()
    )
  """);

  // ─── COMMUNITY CHANNELS ──────────────────────────────────
  await _db!.execute("""
    CREATE TABLE IF NOT EXISTS community_channels (
      id UUID PRIMARY KEY,
      server_id UUID NOT NULL REFERENCES community_servers(id) ON DELETE CASCADE,
      name VARCHAR(100) NOT NULL,
      type VARCHAR(20) DEFAULT 'text',
      description TEXT,
      position INT DEFAULT 0,
      is_nsfw BOOLEAN DEFAULT FALSE,
      created_at TIMESTAMPTZ DEFAULT NOW()
    )
  """);

  // ─── COMMUNITY MESSAGES ──────────────────────────────────
  await _db!.execute("""
    CREATE TABLE IF NOT EXISTS community_messages (
      id UUID PRIMARY KEY,
      channel_id UUID NOT NULL REFERENCES community_channels(id) ON DELETE CASCADE,
      sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      content TEXT,
      media_url TEXT,
      reply_to_id UUID REFERENCES community_messages(id) ON DELETE SET NULL,
      is_pinned BOOLEAN DEFAULT FALSE,
      reactions JSONB DEFAULT '{}',
      is_deleted BOOLEAN DEFAULT FALSE,
      created_at TIMESTAMPTZ DEFAULT NOW()
    )
  """);

  // ─── COMMUNITY MEMBERS ───────────────────────────────────
  await _db!.execute("""
    CREATE TABLE IF NOT EXISTS community_members (
      server_id UUID NOT NULL REFERENCES community_servers(id) ON DELETE CASCADE,
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      role VARCHAR(20) DEFAULT 'member',
      joined_at TIMESTAMPTZ DEFAULT NOW(),
      PRIMARY KEY (server_id, user_id)
    )
  """);

  // ─── PASSWORD RESETS ─────────────────────────────────────
  await _db!.execute("""
    CREATE TABLE IF NOT EXISTS password_resets (
      id UUID PRIMARY KEY,
      email VARCHAR(255) NOT NULL,
      code VARCHAR(6) NOT NULL,
      expires_at TIMESTAMPTZ NOT NULL,
      used BOOLEAN DEFAULT FALSE,
      created_at TIMESTAMPTZ DEFAULT NOW()
    )
  """);

  // ─── EMAILS (Email Client) ───────────────────────────────
  await _db!.execute("""
    CREATE TABLE IF NOT EXISTS emails (
      id UUID PRIMARY KEY,
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      from_address TEXT NOT NULL,
      to_addresses JSONB NOT NULL,
      cc_addresses JSONB DEFAULT '[]',
      subject TEXT,
      body TEXT,
      html_body TEXT,
      attachments JSONB DEFAULT '[]',
      folder VARCHAR(50) DEFAULT 'inbox',
      is_read BOOLEAN DEFAULT FALSE,
      is_starred BOOLEAN DEFAULT FALSE,
      labels JSONB DEFAULT '[]',
      thread_id UUID,
      created_at TIMESTAMPTZ DEFAULT NOW()
    )
  """);

  // ─── AI MESSAGES ─────────────────────────────────────────
  await _db!.execute("""
    CREATE TABLE IF NOT EXISTS ai_messages (
      id UUID PRIMARY KEY,
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      role VARCHAR(20) NOT NULL,
      content TEXT NOT NULL,
      created_at TIMESTAMPTZ DEFAULT NOW()
    )
  """);

  // ─── REFRESH TOKENS ──────────────────────────────────────
  await _db!.execute("""
    CREATE TABLE IF NOT EXISTS refresh_tokens (
      id UUID PRIMARY KEY,
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      token TEXT UNIQUE NOT NULL,
      expires_at TIMESTAMPTZ NOT NULL,
      revoked BOOLEAN DEFAULT FALSE,
      created_at TIMESTAMPTZ DEFAULT NOW()
    )
  """);

  // ─── 2FA SECRETS ─────────────────────────────────────────
  await _db!.execute("""
    CREATE TABLE IF NOT EXISTS two_factor_secrets (
      user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
      secret TEXT NOT NULL,
      enabled BOOLEAN DEFAULT FALSE,
      created_at TIMESTAMPTZ DEFAULT NOW()
    )
  """);

  // ─── DEVICES (FCM tokens) ────────────────────────────────
  await _db!.execute("""
    CREATE TABLE IF NOT EXISTS devices (
      id UUID PRIMARY KEY,
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      token TEXT UNIQUE NOT NULL,
      platform VARCHAR(20) DEFAULT 'android',
      created_at TIMESTAMPTZ DEFAULT NOW()
    )
  """);

  // ─── AUDIT LOG ───────────────────────────────────────────
  await _db!.execute("""
    CREATE TABLE IF NOT EXISTS audit_log (
      id UUID PRIMARY KEY,
      user_id UUID,
      action VARCHAR(100) NOT NULL,
      ip TEXT,
      meta JSONB DEFAULT '{}',
      created_at TIMESTAMPTZ DEFAULT NOW()
    )
  """);

  // ─── BROWSER BOOKMARKS ───────────────────────────────────
  await _db!.execute("""
    CREATE TABLE IF NOT EXISTS browser_bookmarks (
      id UUID PRIMARY KEY,
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      title TEXT NOT NULL,
      url TEXT NOT NULL,
      folder VARCHAR(50) DEFAULT 'default',
      created_at TIMESTAMPTZ DEFAULT NOW()
    )
  """);

  // ─── BROWSER HISTORY ─────────────────────────────────────
  await _db!.execute("""
    CREATE TABLE IF NOT EXISTS browser_history (
      id UUID PRIMARY KEY,
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      title TEXT,
      url TEXT NOT NULL,
      visited_at TIMESTAMPTZ DEFAULT NOW()
    )
  """);

  // ─── NOTIFICATION PREFERENCES ────────────────────────────
  await _db!.execute("""
    CREATE TABLE IF NOT EXISTS notification_prefs (
      user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
      prefs JSONB NOT NULL DEFAULT '{}',
      updated_at TIMESTAMPTZ DEFAULT NOW()
    )
  """);

  // ─── SESSIONS extras ─────────────────────────────────────
  await _db!.execute("ALTER TABLE sessions ADD COLUMN IF NOT EXISTS device TEXT");
  await _db!.execute("ALTER TABLE sessions ADD COLUMN IF NOT EXISTS ip TEXT");
  await _db!.execute("ALTER TABLE sessions ADD COLUMN IF NOT EXISTS last_active TIMESTAMPTZ DEFAULT NOW()");

  // ─── INDEXES ─────────────────────────────────────────────
  await _db!.execute("CREATE INDEX IF NOT EXISTS idx_chat_messages_conv ON chat_messages(conversation_id, created_at DESC)");
  await _db!.execute("CREATE INDEX IF NOT EXISTS idx_chat_members_user ON chat_members(user_id)");
  await _db!.execute("CREATE INDEX IF NOT EXISTS idx_feed_posts_user ON feed_posts(user_id, created_at DESC)");
  await _db!.execute("CREATE INDEX IF NOT EXISTS idx_post_likes_post ON post_likes(post_id)");
  await _db!.execute("CREATE INDEX IF NOT EXISTS idx_comments_post ON post_comments(post_id, created_at)");
  await _db!.execute("CREATE INDEX IF NOT EXISTS idx_follows_follower ON follows(follower_id)");
  await _db!.execute("CREATE INDEX IF NOT EXISTS idx_follows_following ON follows(following_id)");
  await _db!.execute("CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_id, created_at DESC)");
  await _db!.execute("CREATE INDEX IF NOT EXISTS idx_stories_user ON stories(user_id, expires_at)");
  await _db!.execute("CREATE INDEX IF NOT EXISTS idx_comm_messages_channel ON community_messages(channel_id, created_at DESC)");
  await _db!.execute("CREATE INDEX IF NOT EXISTS idx_browser_history_user ON browser_history(user_id, visited_at DESC)");
  await _db!.execute("CREATE INDEX IF NOT EXISTS idx_browser_bookmarks_user ON browser_bookmarks(user_id, created_at DESC)");
  await _db!.execute("CREATE INDEX IF NOT EXISTS idx_emails_user_folder ON emails(user_id, folder, created_at DESC)");
  await _db!.execute("CREATE INDEX IF NOT EXISTS idx_devices_user ON devices(user_id)");
  await _db!.execute("CREATE INDEX IF NOT EXISTS idx_audit_user ON audit_log(user_id, created_at DESC)");

  print("Migrations complete");
}
