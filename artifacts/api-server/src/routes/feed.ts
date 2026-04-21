import { Router } from "express";
import { db } from "@workspace/db";
import { feedPostsTable, postLikesTable, postCommentsTable, followsTable, storiesTable, usersTable } from "@workspace/db/schema";
import { eq, and, desc, inArray } from "drizzle-orm";
import { authenticate, AuthRequest } from "../middlewares/authenticate";
import { z } from "zod/v4";

const router = Router();
router.use(authenticate);

// GET /feed — timeline
router.get("/", async (req: AuthRequest, res) => {
  try {
    const following = await db.select({ followingId: followsTable.followingId })
      .from(followsTable)
      .where(eq(followsTable.followerId, req.userId!));
    const ids = [req.userId!, ...following.map((f) => f.followingId!)];
    const posts = await db.select().from(feedPostsTable)
      .where(and(inArray(feedPostsTable.userId, ids), eq(feedPostsTable.isArchived, false)))
      .orderBy(desc(feedPostsTable.createdAt))
      .limit(30);
    res.json(posts);
  } catch (err) {
    req.log.error(err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// GET /feed/posts/:id
router.get("/posts/:id", async (req: AuthRequest, res) => {
  try {
    const [post] = await db.select().from(feedPostsTable).where(eq(feedPostsTable.id, req.params.id)).limit(1);
    if (!post) { res.status(404).json({ error: "Post not found" }); return; }
    res.json(post);
  } catch (err) {
    req.log.error(err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// POST /feed/posts
router.post("/posts", async (req: AuthRequest, res) => {
  try {
    const schema = z.object({
      caption: z.string().optional(),
      mediaUrls: z.array(z.string()).default([]),
      type: z.enum(["post", "reel"]).default("post"),
    });
    const parsed = schema.safeParse(req.body);
    if (!parsed.success) { res.status(400).json({ error: "Validation failed" }); return; }
    const [post] = await db.insert(feedPostsTable).values({ userId: req.userId, ...parsed.data }).returning();
    res.status(201).json(post);
  } catch (err) {
    req.log.error(err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// DELETE /feed/posts/:id
router.delete("/posts/:id", async (req: AuthRequest, res) => {
  try {
    await db.update(feedPostsTable).set({ isArchived: true })
      .where(and(eq(feedPostsTable.id, req.params.id), eq(feedPostsTable.userId, req.userId!)));
    res.json({ message: "Post archived" });
  } catch (err) {
    req.log.error(err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// POST /feed/posts/:id/like
router.post("/posts/:id/like", async (req: AuthRequest, res) => {
  try {
    const existing = await db.select().from(postLikesTable)
      .where(and(eq(postLikesTable.postId, req.params.id), eq(postLikesTable.userId, req.userId!))).limit(1);
    if (existing.length > 0) {
      await db.delete(postLikesTable).where(and(eq(postLikesTable.postId, req.params.id), eq(postLikesTable.userId, req.userId!)));
      await db.update(feedPostsTable).set({ likesCount: 0 }).where(eq(feedPostsTable.id, req.params.id));
      res.json({ liked: false });
    } else {
      await db.insert(postLikesTable).values({ postId: req.params.id, userId: req.userId });
      res.json({ liked: true });
    }
  } catch (err) {
    req.log.error(err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// GET /feed/posts/:id/comments
router.get("/posts/:id/comments", async (req: AuthRequest, res) => {
  try {
    const comments = await db.select().from(postCommentsTable)
      .where(eq(postCommentsTable.postId, req.params.id))
      .orderBy(desc(postCommentsTable.createdAt));
    res.json(comments);
  } catch (err) {
    req.log.error(err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// POST /feed/posts/:id/comments
router.post("/posts/:id/comments", async (req: AuthRequest, res) => {
  try {
    const schema = z.object({ content: z.string().min(1), parentId: z.string().optional() });
    const parsed = schema.safeParse(req.body);
    if (!parsed.success) { res.status(400).json({ error: "Validation failed" }); return; }
    const [comment] = await db.insert(postCommentsTable).values({ postId: req.params.id, userId: req.userId, ...parsed.data }).returning();
    res.status(201).json(comment);
  } catch (err) {
    req.log.error(err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// POST /feed/follow/:userId
router.post("/follow/:userId", async (req: AuthRequest, res) => {
  try {
    const existing = await db.select().from(followsTable)
      .where(and(eq(followsTable.followerId, req.userId!), eq(followsTable.followingId, req.params.userId))).limit(1);
    if (existing.length > 0) {
      await db.delete(followsTable).where(and(eq(followsTable.followerId, req.userId!), eq(followsTable.followingId, req.params.userId)));
      res.json({ following: false });
    } else {
      await db.insert(followsTable).values({ followerId: req.userId, followingId: req.params.userId });
      res.json({ following: true });
    }
  } catch (err) {
    req.log.error(err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// GET /feed/stories
router.get("/stories", async (req: AuthRequest, res) => {
  try {
    const stories = await db.select().from(storiesTable)
      .where(eq(storiesTable.userId, req.userId!))
      .orderBy(desc(storiesTable.createdAt));
    res.json(stories);
  } catch (err) {
    req.log.error(err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// POST /feed/stories
router.post("/stories", async (req: AuthRequest, res) => {
  try {
    const schema = z.object({
      type: z.enum(["image", "video"]).default("image"),
      mediaUrl: z.string(),
      caption: z.string().optional(),
    });
    const parsed = schema.safeParse(req.body);
    if (!parsed.success) { res.status(400).json({ error: "Validation failed" }); return; }
    const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000);
    const [story] = await db.insert(storiesTable).values({ userId: req.userId, ...parsed.data, expiresAt }).returning();
    res.status(201).json(story);
  } catch (err) {
    req.log.error(err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// GET /feed/explore
router.get("/explore", async (req: AuthRequest, res) => {
  try {
    const posts = await db.select().from(feedPostsTable)
      .where(eq(feedPostsTable.isArchived, false))
      .orderBy(desc(feedPostsTable.likesCount))
      .limit(50);
    res.json(posts);
  } catch (err) {
    req.log.error(err);
    res.status(500).json({ error: "Internal server error" });
  }
});

export default router;
