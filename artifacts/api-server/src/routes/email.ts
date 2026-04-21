import { Router } from "express";
import { db } from "@workspace/db";
import { emailsTable } from "@workspace/db/schema";
import { eq, and, desc } from "drizzle-orm";
import { authenticate, AuthRequest } from "../middlewares/authenticate";
import { z } from "zod/v4";

const router = Router();
router.use(authenticate);

// GET /email?folder=inbox
router.get("/", async (req: AuthRequest, res) => {
  try {
    const folder = (req.query.folder as string) || "inbox";
    const emails = await db.select().from(emailsTable)
      .where(and(eq(emailsTable.userId, req.userId!), eq(emailsTable.folder, folder)))
      .orderBy(desc(emailsTable.createdAt));
    res.json(emails);
  } catch (err) {
    req.log.error(err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// GET /email/:id
router.get("/:id", async (req: AuthRequest, res) => {
  try {
    const [email] = await db.select().from(emailsTable)
      .where(and(eq(emailsTable.id, req.params.id), eq(emailsTable.userId, req.userId!))).limit(1);
    if (!email) { res.status(404).json({ error: "Email not found" }); return; }
    // mark as read
    await db.update(emailsTable).set({ isRead: true }).where(eq(emailsTable.id, req.params.id));
    res.json({ ...email, isRead: true });
  } catch (err) {
    req.log.error(err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// POST /email (send/save)
router.post("/", async (req: AuthRequest, res) => {
  try {
    const schema = z.object({
      fromAddress: z.string(),
      toAddresses: z.array(z.string()),
      ccAddresses: z.array(z.string()).default([]),
      subject: z.string().optional(),
      body: z.string().optional(),
      htmlBody: z.string().optional(),
      folder: z.string().default("sent"),
    });
    const parsed = schema.safeParse(req.body);
    if (!parsed.success) { res.status(400).json({ error: "Validation failed" }); return; }
    const [email] = await db.insert(emailsTable).values({ userId: req.userId, ...parsed.data }).returning();
    res.status(201).json(email);
  } catch (err) {
    req.log.error(err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// PUT /email/:id (star, label, move folder)
router.put("/:id", async (req: AuthRequest, res) => {
  try {
    const schema = z.object({
      isStarred: z.boolean().optional(),
      isRead: z.boolean().optional(),
      folder: z.string().optional(),
    });
    const parsed = schema.safeParse(req.body);
    if (!parsed.success) { res.status(400).json({ error: "Validation failed" }); return; }
    const [updated] = await db.update(emailsTable).set(parsed.data)
      .where(and(eq(emailsTable.id, req.params.id), eq(emailsTable.userId, req.userId!)))
      .returning();
    res.json(updated);
  } catch (err) {
    req.log.error(err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// DELETE /email/:id (move to trash)
router.delete("/:id", async (req: AuthRequest, res) => {
  try {
    await db.update(emailsTable).set({ folder: "trash" })
      .where(and(eq(emailsTable.id, req.params.id), eq(emailsTable.userId, req.userId!)));
    res.json({ message: "Moved to trash" });
  } catch (err) {
    req.log.error(err);
    res.status(500).json({ error: "Internal server error" });
  }
});

export default router;
