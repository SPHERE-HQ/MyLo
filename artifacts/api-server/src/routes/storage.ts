import { Router } from "express";
import { db } from "@workspace/db";
import { userFilesTable } from "@workspace/db/schema";
import { eq, and } from "drizzle-orm";
import { authenticate, AuthRequest } from "../middlewares/authenticate";
import { z } from "zod/v4";

const router = Router();
router.use(authenticate);

// GET /storage/files
router.get("/files", async (req: AuthRequest, res) => {
  try {
    const files = await db.select().from(userFilesTable)
      .where(eq(userFilesTable.userId, req.userId!));
    res.json(files);
  } catch (err) {
    req.log.error(err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// POST /storage/files
router.post("/files", async (req: AuthRequest, res) => {
  try {
    const schema = z.object({
      name: z.string(),
      url: z.string(),
      size: z.number().optional(),
      mimeType: z.string().optional(),
      source: z.string().optional(),
    });
    const parsed = schema.safeParse(req.body);
    if (!parsed.success) { res.status(400).json({ error: "Validation failed" }); return; }
    const [file] = await db.insert(userFilesTable).values({ userId: req.userId, ...parsed.data }).returning();
    res.status(201).json(file);
  } catch (err) {
    req.log.error(err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// DELETE /storage/files/:id
router.delete("/files/:id", async (req: AuthRequest, res) => {
  try {
    await db.delete(userFilesTable)
      .where(and(eq(userFilesTable.id, req.params.id), eq(userFilesTable.userId, req.userId!)));
    res.json({ message: "File deleted" });
  } catch (err) {
    req.log.error(err);
    res.status(500).json({ error: "Internal server error" });
  }
});

export default router;
