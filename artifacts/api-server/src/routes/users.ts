import { Router } from "express";
import { db } from "@workspace/db";
import { usersTable, followsTable, feedPostsTable } from "@workspace/db/schema";
import { eq, and, like } from "drizzle-orm";
import { authenticate, AuthRequest } from "../middlewares/authenticate";

const router = Router();
router.use(authenticate);

// GET /users/search?q=
router.get("/search", async (req: AuthRequest, res) => {
  try {
    const q = (req.query.q as string) || "";
    if (!q) { res.json([]); return; }
    const users = await db.select({
      id: usersTable.id,
      username: usersTable.username,
      displayName: usersTable.displayName,
      avatarUrl: usersTable.avatarUrl,
      bio: usersTable.bio,
    }).from(usersTable)
      .where(like(usersTable.username, `%${q}%`))
      .limit(20);
    res.json(users);
  } catch (err) {
    req.log.error(err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// GET /users/:id
router.get("/:id", async (req: AuthRequest, res) => {
  try {
    const [user] = await db.select({
      id: usersTable.id,
      username: usersTable.username,
      displayName: usersTable.displayName,
      avatarUrl: usersTable.avatarUrl,
      bio: usersTable.bio,
      isVerified: usersTable.isVerified,
      createdAt: usersTable.createdAt,
    }).from(usersTable).where(eq(usersTable.id, req.params.id)).limit(1);
    if (!user) { res.status(404).json({ error: "User not found" }); return; }

    const posts = await db.select().from(feedPostsTable)
      .where(and(eq(feedPostsTable.userId, req.params.id), eq(feedPostsTable.isArchived, false)));
    const followers = await db.select().from(followsTable).where(eq(followsTable.followingId, req.params.id));
    const following = await db.select().from(followsTable).where(eq(followsTable.followerId, req.params.id));
    const isFollowing = followers.some((f) => f.followerId === req.userId);

    res.json({ ...user, postsCount: posts.length, followersCount: followers.length, followingCount: following.length, isFollowing });
  } catch (err) {
    req.log.error(err);
    res.status(500).json({ error: "Internal server error" });
  }
});

export default router;
