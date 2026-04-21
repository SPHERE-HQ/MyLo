import { Router } from "express";
import { db } from "@workspace/db";
import { notificationsTable } from "@workspace/db/schema";
import { eq, and, desc } from "drizzle-orm";
import { authenticate, AuthRequest } from "../middlewares/authenticate";

const router = Router();
router.use(authenticate);

// GET /notifications
router.get("/", async (req: AuthRequest, res) => {
  try {
    const notifications = await db.select().from(notificationsTable)
      .where(eq(notificationsTable.userId, req.userId!))
      .orderBy(desc(notificationsTable.createdAt))
      .limit(50);
    res.json(notifications);
  } catch (err) {
    req.log.error(err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// PUT /notifications/:id/read
router.put("/:id/read", async (req: AuthRequest, res) => {
  try {
    await db.update(notificationsTable).set({ isRead: true })
      .where(and(eq(notificationsTable.id, req.params.id), eq(notificationsTable.userId, req.userId!)));
    res.json({ message: "Marked as read" });
  } catch (err) {
    req.log.error(err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// PUT /notifications/read-all
router.put("/read-all", async (req: AuthRequest, res) => {
  try {
    await db.update(notificationsTable).set({ isRead: true })
      .where(eq(notificationsTable.userId, req.userId!));
    res.json({ message: "All marked as read" });
  } catch (err) {
    req.log.error(err);
    res.status(500).json({ error: "Internal server error" });
  }
});

export default router;
