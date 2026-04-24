import "dart:io";
import "package:postgres/postgres.dart";

late Connection _db;

Future<Connection> getDb() async => _db;

Future<void> initDb() async {
  final url = Platform.environment["DATABASE_URL"] ?? "";
  if (url.isEmpty) { print("WARNING: DATABASE_URL not set"); return; }
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
  print("Database connected");
  await _runMigrations();
}

Future<void> _runMigrations() async {
  print("Running migrations...");

  // ─── USERS ───────────────────────────────────────────────
  await _db.execute("""
    CREATE TABLE IF NOT EXISTS users (
      id UUID PRIMARY KEY,
      username VARCHAR(50) UNIQUE NOT NULL,
      email VARCHAR(255) UNIQUE NOT NULL,
      password_hash TEXT NOT NULL,
      display_name VARCHAR(100),
      avatar_url TEXT,
      bio TEXT,
      phone VARCHAR(20),
      is_verified BOOLEAN DEFAULT FALSE,
      two_factor_enabled BOOLEAN DEFAULT FALSE,
      created_at TIMESTAMPTZ DEFAULT NOW(),
      updated_at TIMESTAMPTZ DEFAULT NOW()
    )
  """);
  await _db.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS two_factor_enabled BOOLEAN DEFAULT FALSE");

  // ─── SESSIONS ────────────────────────────────────────────
  await _db.execute("""
    CREATE TABLE IF NOT EXISTS sessions (
      id UUID PRIMARY KEY,
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      token TEXT NOT NULL,
      expires_at TIMESTAMPTZ NOT NULL,
      created_at TIMESTAMPTZ DEFAULT NOW()
    )
  """);

  // ─── EMAIL VERIFICATIONS ─────────────────────────────────
  await _db.execute("""
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
  await _db.execute("""
    CREATE TABLE IF NOT EXISTS follows (
      id UUID PRIMARY KEY,
      follower_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      following_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      created_at TIMESTAMPTZ DEFAULT NOW(),
      UNIQUE(follower_id, following_id)
    )
  """);

  // ─── FEED POSTS ──────────────────────────────────────────
  await _db.execute("""
    CREATE TABLE IF NOT EXISTS posts (
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
  await _db.execute("ALTER TABLE posts ADD COLUMN IF NOT EXISTS caption TEXT");
  await _db.execute("ALTER TABLE posts ADD COLUMN IF NOT EXISTS media_urls JSONB DEFAULT '[]'");
  await _db.execute("ALTER TABLE posts ADD COLUMN IF NOT EXISTS type VARCHAR(20) DEFAULT 'post'");
  await _db.execute("ALTER TABLE posts ADD COLUMN IF NOT EXISTS likes_count INT DEFAULT 0");
  await _db.execute("ALTER TABLE posts ADD COLUMN IF NOT EXISTS comments_count INT DEFAULT 0");
  await _db.execute("ALTER TABLE posts ADD COLUMN IF NOT EXISTS is_archived BOOLEAN DEFAULT FALSE");

  // ─── POST LIKES ──────────────────────────────────────────
  await _db.execute("""
    CREATE TABLE IF NOT EXISTS post_likes (
      id UUID PRIMARY KEY,
      post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      created_at TIMESTAMPTZ DEFAULT NOW(),
      UNIQUE(post_id, user_id)
    )
  """);

  // ─── POST COMMENTS ───────────────────────────────────────
  await _db.execute("""
    CREATE TABLE IF NOT EXISTS post_comments (
      id UUID PRIMARY KEY,
      post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      parent_id UUID REFERENCES post_comments(id) ON DELETE CASCADE,
      content TEXT NOT NULL,
      created_at TIMESTAMPTZ DEFAULT NOW()
    )
  """);

  // ─── STORIES ─────────────────────────────────────────────
  await _db.execute("""
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

  // ─── CHAT CONVERSATIONS ──────────────────────────────────
  await _db.execute("""
    CREATE TABLE IF NOT EXISTS conversations (
      id UUID PRIMARY KEY,
      type VARCHAR(20) DEFAULT 'private',
      name VARCHAR(100),
      avatar_url TEXT,
      created_by UUID REFERENCES users(id) ON DELETE SET NULL,
      created_at TIMESTAMPTZ DEFAULT NOW()
    )
  """);
  await _db.execute("ALTER TABLE conversations ADD COLUMN IF NOT EXISTS type VARCHAR(20) DEFAULT 'private'");
  await _db.execute("ALTER TABLE conversations ADD COLUMN IF NOT EXISTS name VARCHAR(100)");
  await _db.execute("ALTER TABLE conversations ADD COLUMN IF NOT EXISTS avatar_url TEXT");
  await _db.execute("ALTER TABLE conversations ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES users(id) ON DELETE SET NULL");

  // ─── CHAT MEMBERS ────────────────────────────────────────
  await _db.execute("""
    CREATE TABLE IF NOT EXISTS conversation_members (
      conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      role VARCHAR(20) DEFAULT 'member',
      joined_at TIMESTAMPTZ DEFAULT NOW(),
      PRIMARY KEY (conversation_id, user_id)
    )
  """);
  await _db.execute("ALTER TABLE conversation_members ADD COLUMN IF NOT EXISTS role VARCHAR(20) DEFAULT 'member'");

  // ─── CHAT MESSAGES ───────────────────────────────────────
  await _db.execute("""
    CREATE TABLE IF NOT EXISTS messages (
      id UUID PRIMARY KEY,
      conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
      sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      type VARCHAR(20) DEFAULT 'text',
      content TEXT,
      media_url TEXT,
      reply_to_id UUID REFERENCES messages(id) ON DELETE SET NULL,
      is_deleted BOOLEAN DEFAULT FALSE,
      read_by JSONB DEFAULT '[]',
      created_at TIMESTAMPTZ DEFAULT NOW()
    )
  """);
  await _db.execute("ALTER TABLE messages ADD COLUMN IF NOT EXISTS type VARCHAR(20) DEFAULT 'text'");
  await _db.execute("ALTER TABLE messages ADD COLUMN IF NOT EXISTS media_url TEXT");
  await _db.execute("ALTER TABLE messages ADD COLUMN IF NOT EXISTS reply_to_id UUID REFERENCES messages(id) ON DELETE SET NULL");
  await _db.execute("ALTER TABLE messages ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN DEFAULT FALSE");
  await _db.execute("ALTER TABLE messages ADD COLUMN IF NOT EXISTS read_by JSONB DEFAULT '[]'");

  // ─── WALLETS ─────────────────────────────────────────────
  await _db.execute("""
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
  await _db.execute("ALTER TABLE wallets ADD COLUMN IF NOT EXISTS id UUID DEFAULT gen_random_uuid()");
  await _db.execute("ALTER TABLE wallets ADD COLUMN IF NOT EXISTS currency VARCHAR(10) DEFAULT 'IDR'");
  await _db.execute("ALTER TABLE wallets ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT TRUE");
  await _db.execute("ALTER TABLE wallets ADD COLUMN IF NOT EXISTS pin_hash TEXT");

  // ─── WALLET TRANSACTIONS ─────────────────────────────────
  await _db.execute("""
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
  await _db.execute("""
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
  await _db.execute("ALTER TABLE notifications ADD COLUMN IF NOT EXISTS data JSONB DEFAULT '{}'");

  // ─── USER FILES ──────────────────────────────────────────
  await _db.execute("""
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
  await _db.execute("""
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
  await _db.execute("""
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
  await _db.execute("""
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
  await _db.execute("""
    CREATE TABLE IF NOT EXISTS community_members (
      server_id UUID NOT NULL REFERENCES community_servers(id) ON DELETE CASCADE,
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      role VARCHAR(20) DEFAULT 'member',
      joined_at TIMESTAMPTZ DEFAULT NOW(),
      PRIMARY KEY (server_id, user_id)
    )
  """);

  // ─── PASSWORD RESETS ─────────────────────────────────────
  await _db.execute("""
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
  await _db.execute("""
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
  await _db.execute("""
    CREATE TABLE IF NOT EXISTS ai_messages (
      id UUID PRIMARY KEY,
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      role VARCHAR(20) NOT NULL,
      content TEXT NOT NULL,
      created_at TIMESTAMPTZ DEFAULT NOW()
    )
  """);

  // ─── INDEXES ─────────────────────────────────────────────
  await _db.execute("CREATE INDEX IF NOT EXISTS idx_messages_conv ON messages(conversation_id, created_at DESC)");
  await _db.execute("CREATE INDEX IF NOT EXISTS idx_posts_user ON posts(user_id, created_at DESC)");
  await _db.execute("CREATE INDEX IF NOT EXISTS idx_post_likes_post ON post_likes(post_id)");
  await _db.execute("CREATE INDEX IF NOT EXISTS idx_comments_post ON post_comments(post_id, created_at)");
  await _db.execute("CREATE INDEX IF NOT EXISTS idx_follows_follower ON follows(follower_id)");
  await _db.execute("CREATE INDEX IF NOT EXISTS idx_follows_following ON follows(following_id)");
  await _db.execute("CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_id, created_at DESC)");
  await _db.execute("CREATE INDEX IF NOT EXISTS idx_stories_user ON stories(user_id, expires_at)");
  await _db.execute("CREATE INDEX IF NOT EXISTS idx_comm_messages_channel ON community_messages(channel_id, created_at DESC)");

  print("Migrations complete");
}

