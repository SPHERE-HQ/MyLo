import { Router } from "express";
import { db } from "@workspace/db";
import {
  chatConversationsTable,
  chatMembersTable,
  chatMessagesTable,
  usersTable,
} from "@workspace/db/schema";
import { eq, and, desc } from "drizzle-orm";
import { authenticate, AuthRequest } from "../middlewares/authenticate";
import { z } from "zod/v4";

const router = Router();
router.use(authenticate);

// GET /chat/conversations
router.get("/conversations", async (req: AuthRequest, res) => {
  try {
    const memberships = await db.select({ conversationId: chatMembersTable.conversationId })
      .from(chatMembersTable)
      .where(eq(chatMembersTable.userId, req.userId!));

    const convIds = memberships.map((m) => m.conversationId!);
    if (convIds.length === 0) {
      res.json([]);
      return;
    }

    const conversations = await Promise.all(convIds.map(async (id) => {
      const [conv] = await db.select().from(chatConversationsTable).where(eq(chatConversationsTable.id, id)).limit(1);
      const [lastMsg] = await db.select().from(chatMessagesTable)
        .where(eq(chatMessagesTable.conversationId, id))
        .orderBy(desc(chatMessagesTable.createdAt))
        .limit(1);
      return { ...conv, lastMessage: lastMsg || null };
    }));

    res.json(conversations);
  } catch (err) {
    req.log.error(err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// POST /chat/conversations
router.post("/conversations", async (req: AuthRequest, res) => {
  try {
    const schema = z.object({
      type: z.enum(["private", "group"]),
      name: z.string().optional(),
      memberIds: z.array(z.string()).min(1),
    });
    const parsed = schema.safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: "Validation failed" });
      return;
    }
    const { type, name, memberIds } = parsed.data;
    const [conv] = await db.insert(chatConversationsTable).values({ type, name, createdBy: req.userId }).returning();

    const allMembers = Array.from(new Set([req.userId!, ...memberIds]));
    await db.insert(chatMembersTable).values(allMembers.map((userId, i) => ({
      conversationId: conv.id,
      userId,
      role: i === 0 ? "admin" : "member",
    })));

    res.status(201).json(conv);
  } catch (err) {
    req.log.error(err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// GET /chat/conversations/:id/messages
router.get("/conversations/:id/messages", async (req: AuthRequest, res) => {
  try {
    const { id } = req.params;
    const limit = parseInt(req.query.limit as string || "50");
    const messages = await db.select().from(chatMessagesTable)
      .where(and(eq(chatMessagesTable.conversationId, id), eq(chatMessagesTable.isDeleted, false)))
      .orderBy(desc(chatMessagesTable.createdAt))
      .limit(limit);
    res.json(messages.reverse());
  } catch (err) {
    req.log.error(err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// POST /chat/conversations/:id/messages
router.post("/conversations/:id/messages", async (req: AuthRequest, res) => {
  try {
    const { id } = req.params;
    const schema = z.object({
      type: z.enum(["text", "image", "video", "audio", "file", "location"]).default("text"),
      content: z.string().optional(),
      mediaUrl: z.string().optional(),
      replyToId: z.string().optional(),
    });
    const parsed = schema.safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: "Validation failed" });
      return;
    }
    const [msg] = await db.insert(chatMessagesTable).values({
      conversationId: id,
      senderId: req.userId,
      ...parsed.data,
    }).returning();
    res.status(201).json(msg);
  } catch (err) {
    req.log.error(err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// DELETE /chat/messages/:id
router.delete("/messages/:id", async (req: AuthRequest, res) => {
  try {
    await db.update(chatMessagesTable)
      .set({ isDeleted: true })
      .where(and(eq(chatMessagesTable.id, req.params.id), eq(chatMessagesTable.senderId, req.userId!)));
    res.json({ message: "Message deleted" });
  } catch (err) {
    req.log.error(err);
    res.status(500).json({ error: "Internal server error" });
  }
});

export default router;
