import { pgTable, uuid, varchar, text, boolean, timestamp, jsonb } from "drizzle-orm/pg-core";
import { createInsertSchema } from "drizzle-zod";
import { z } from "zod/v4";
import { usersTable } from "./users";

export const chatConversationsTable = pgTable("chat_conversations", {
  id: uuid("id").primaryKey().defaultRandom(),
  type: varchar("type", { length: 20 }).notNull(),
  name: varchar("name", { length: 100 }),
  avatarUrl: text("avatar_url"),
  createdBy: uuid("created_by").references(() => usersTable.id),
  createdAt: timestamp("created_at").defaultNow(),
});

export const chatMembersTable = pgTable("chat_members", {
  id: uuid("id").primaryKey().defaultRandom(),
  conversationId: uuid("conversation_id").references(() => chatConversationsTable.id),
  userId: uuid("user_id").references(() => usersTable.id),
  role: varchar("role", { length: 20 }).default("member"),
  joinedAt: timestamp("joined_at").defaultNow(),
});

export const chatMessagesTable = pgTable("chat_messages", {
  id: uuid("id").primaryKey().defaultRandom(),
  conversationId: uuid("conversation_id").references(() => chatConversationsTable.id),
  senderId: uuid("sender_id").references(() => usersTable.id),
  type: varchar("type", { length: 20 }).default("text"),
  content: text("content"),
  mediaUrl: text("media_url"),
  replyToId: uuid("reply_to_id"),
  isDeleted: boolean("is_deleted").default(false),
  readBy: jsonb("read_by").default([]),
  createdAt: timestamp("created_at").defaultNow(),
  updatedAt: timestamp("updated_at").defaultNow(),
});

export const insertChatConversationSchema = createInsertSchema(chatConversationsTable).omit({ id: true, createdAt: true });
export const insertChatMemberSchema = createInsertSchema(chatMembersTable).omit({ id: true, joinedAt: true });
export const insertChatMessageSchema = createInsertSchema(chatMessagesTable).omit({ id: true, createdAt: true, updatedAt: true });

export type InsertChatConversation = z.infer<typeof insertChatConversationSchema>;
export type InsertChatMember = z.infer<typeof insertChatMemberSchema>;
export type InsertChatMessage = z.infer<typeof insertChatMessageSchema>;
export type ChatConversation = typeof chatConversationsTable.$inferSelect;
export type ChatMember = typeof chatMembersTable.$inferSelect;
export type ChatMessage = typeof chatMessagesTable.$inferSelect;
