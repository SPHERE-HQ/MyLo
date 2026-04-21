import { pgTable, uuid, varchar, text, boolean, timestamp, jsonb, integer } from "drizzle-orm/pg-core";
import { createInsertSchema } from "drizzle-zod";
import { z } from "zod/v4";
import { usersTable } from "./users";

export const communityServersTable = pgTable("community_servers", {
  id: uuid("id").primaryKey().defaultRandom(),
  name: varchar("name", { length: 100 }).notNull(),
  description: text("description"),
  iconUrl: text("icon_url"),
  bannerUrl: text("banner_url"),
  ownerId: uuid("owner_id").references(() => usersTable.id),
  isPublic: boolean("is_public").default(true),
  inviteCode: varchar("invite_code", { length: 20 }).unique(),
  createdAt: timestamp("created_at").defaultNow(),
});

export const communityChannelsTable = pgTable("community_channels", {
  id: uuid("id").primaryKey().defaultRandom(),
  serverId: uuid("server_id").references(() => communityServersTable.id),
  name: varchar("name", { length: 100 }).notNull(),
  type: varchar("type", { length: 20 }).default("text"),
  description: text("description"),
  position: integer("position").default(0),
  isNsfw: boolean("is_nsfw").default(false),
  createdAt: timestamp("created_at").defaultNow(),
});

export const communityMessagesTable = pgTable("community_messages", {
  id: uuid("id").primaryKey().defaultRandom(),
  channelId: uuid("channel_id").references(() => communityChannelsTable.id),
  senderId: uuid("sender_id").references(() => usersTable.id),
  content: text("content"),
  mediaUrl: text("media_url"),
  replyToId: uuid("reply_to_id"),
  isPinned: boolean("is_pinned").default(false),
  reactions: jsonb("reactions").default({}),
  isDeleted: boolean("is_deleted").default(false),
  createdAt: timestamp("created_at").defaultNow(),
});

export const insertCommunityServerSchema = createInsertSchema(communityServersTable).omit({ id: true, createdAt: true });
export const insertCommunityChannelSchema = createInsertSchema(communityChannelsTable).omit({ id: true, createdAt: true });
export const insertCommunityMessageSchema = createInsertSchema(communityMessagesTable).omit({ id: true, createdAt: true });

export type InsertCommunityServer = z.infer<typeof insertCommunityServerSchema>;
export type InsertCommunityChannel = z.infer<typeof insertCommunityChannelSchema>;
export type InsertCommunityMessage = z.infer<typeof insertCommunityMessageSchema>;
export type CommunityServer = typeof communityServersTable.$inferSelect;
export type CommunityChannel = typeof communityChannelsTable.$inferSelect;
export type CommunityMessage = typeof communityMessagesTable.$inferSelect;
