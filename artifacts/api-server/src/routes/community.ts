import { Router } from "express";
import { db } from "@workspace/db";
import { communityServersTable, communityChannelsTable, communityMessagesTable } from "@workspace/db/schema";
import { eq, and, desc } from "drizzle-orm";
import { authenticate, AuthRequest } from "../middlewares/authenticate";
import { z } from "zod/v4";

const router = Router();
router.use(authenticate);

// GET /community/servers
router.get("/servers", async (req: AuthRequest, res) => {
  try {
    const servers = await db.select().from(communityServersTable)
      .where(eq(communityServersTable.isPublic, true));
    res.json(servers);
  } catch (err) {
    req.log.error(err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// POST /community/servers
router.post("/servers", async (req: AuthRequest, res) => {
  try {
    const schema = z.object({
      name: z.string().min(1).max(100),
      description: z.string().optional(),
      isPublic: z.boolean().default(true),
    });
    const parsed = schema.safeParse(req.body);
    if (!parsed.success) { res.status(400).json({ error: "Validation failed" }); return; }
    const inviteCode = Math.random().toString(36).substring(2, 10).toUpperCase();
    const [server] = await db.insert(communityServersTable).values({
      ...parsed.data,
      ownerId: req.userId,
      inviteCode,
    }).returning();
    res.status(201).json(server);
  } catch (err) {
    req.log.error(err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// GET /community/servers/:id
router.get("/servers/:id", async (req: AuthRequest, res) => {
  try {
    const [server] = await db.select().from(communityServersTable).where(eq(communityServersTable.id, req.params.id)).limit(1);
    if (!server) { res.status(404).json({ error: "Server not found" }); return; }
    const channels = await db.select().from(communityChannelsTable).where(eq(communityChannelsTable.serverId, req.params.id));
    res.json({ ...server, channels });
  } catch (err) {
    req.log.error(err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// POST /community/servers/:id/channels
router.post("/servers/:id/channels", async (req: AuthRequest, res) => {
  try {
    const schema = z.object({
      name: z.string().min(1).max(100),
      type: z.enum(["text", "voice"]).default("text"),
      description: z.string().optional(),
    });
    const parsed = schema.safeParse(req.body);
    if (!parsed.success) { res.status(400).json({ error: "Validation failed" }); return; }
    const [channel] = await db.insert(communityChannelsTable).values({ serverId: req.params.id, ...parsed.data }).returning();
    res.status(201).json(channel);
  } catch (err) {
    req.log.error(err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// GET /community/channels/:id/messages
router.get("/channels/:id/messages", async (req: AuthRequest, res) => {
  try {
    const messages = await db.select().from(communityMessagesTable)
      .where(and(eq(communityMessagesTable.channelId, req.params.id), eq(communityMessagesTable.isDeleted, false)))
      .orderBy(desc(communityMessagesTable.createdAt))
      .limit(50);
    res.json(messages.reverse());
  } catch (err) {
    req.log.error(err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// POST /community/channels/:id/messages
router.post("/channels/:id/messages", async (req: AuthRequest, res) => {
  try {
    const schema = z.object({
      content: z.string().optional(),
      mediaUrl: z.string().optional(),
      replyToId: z.string().optional(),
    });
    const parsed = schema.safeParse(req.body);
    if (!parsed.success) { res.status(400).json({ error: "Validation failed" }); return; }
    const [msg] = await db.insert(communityMessagesTable).values({ channelId: req.params.id, senderId: req.userId, ...parsed.data }).returning();
    res.status(201).json(msg);
  } catch (err) {
    req.log.error(err);
    res.status(500).json({ error: "Internal server error" });
  }
});

export default router;
