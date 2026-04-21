import { pgTable, uuid, text, timestamp, bigint, varchar } from "drizzle-orm/pg-core";
import { createInsertSchema } from "drizzle-zod";
import { z } from "zod/v4";
import { usersTable } from "./users";

export const userFilesTable = pgTable("user_files", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id").references(() => usersTable.id),
  name: text("name").notNull(),
  url: text("url").notNull(),
  size: bigint("size", { mode: "number" }),
  mimeType: text("mime_type"),
  source: varchar("source", { length: 30 }),
  createdAt: timestamp("created_at").defaultNow(),
});

export const insertUserFileSchema = createInsertSchema(userFilesTable).omit({ id: true, createdAt: true });
export type InsertUserFile = z.infer<typeof insertUserFileSchema>;
export type UserFile = typeof userFilesTable.$inferSelect;
