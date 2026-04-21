import { pgTable, uuid, text, boolean, timestamp, jsonb, integer, varchar } from "drizzle-orm/pg-core";
import { createInsertSchema } from "drizzle-zod";
import { z } from "zod/v4";
import { usersTable } from "./users";

export const storiesTable = pgTable("stories", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id").references(() => usersTable.id),
  type: varchar("type", { length: 20 }).default("image"),
  mediaUrl: text("media_url").notNull(),
  caption: text("caption"),
  views: jsonb("views").default([]),
  expiresAt: timestamp("expires_at"),
  createdAt: timestamp("created_at").defaultNow(),
});

export const feedPostsTable = pgTable("feed_posts", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id").references(() => usersTable.id),
  caption: text("caption"),
  mediaUrls: jsonb("media_urls").default([]),
  type: varchar("type", { length: 20 }).default("post"),
  likesCount: integer("likes_count").default(0),
  commentsCount: integer("comments_count").default(0),
  isArchived: boolean("is_archived").default(false),
  createdAt: timestamp("created_at").defaultNow(),
});

export const postLikesTable = pgTable("post_likes", {
  id: uuid("id").primaryKey().defaultRandom(),
  postId: uuid("post_id").references(() => feedPostsTable.id),
  userId: uuid("user_id").references(() => usersTable.id),
  createdAt: timestamp("created_at").defaultNow(),
});

export const postCommentsTable = pgTable("post_comments", {
  id: uuid("id").primaryKey().defaultRandom(),
  postId: uuid("post_id").references(() => feedPostsTable.id),
  userId: uuid("user_id").references(() => usersTable.id),
  parentId: uuid("parent_id"),
  content: text("content").notNull(),
  createdAt: timestamp("created_at").defaultNow(),
});

export const followsTable = pgTable("follows", {
  id: uuid("id").primaryKey().defaultRandom(),
  followerId: uuid("follower_id").references(() => usersTable.id),
  followingId: uuid("following_id").references(() => usersTable.id),
  createdAt: timestamp("created_at").defaultNow(),
});

export const insertStorySchema = createInsertSchema(storiesTable).omit({ id: true, createdAt: true });
export const insertFeedPostSchema = createInsertSchema(feedPostsTable).omit({ id: true, createdAt: true });
export const insertPostLikeSchema = createInsertSchema(postLikesTable).omit({ id: true, createdAt: true });
export const insertPostCommentSchema = createInsertSchema(postCommentsTable).omit({ id: true, createdAt: true });
export const insertFollowSchema = createInsertSchema(followsTable).omit({ id: true, createdAt: true });

export type InsertStory = z.infer<typeof insertStorySchema>;
export type InsertFeedPost = z.infer<typeof insertFeedPostSchema>;
export type InsertPostLike = z.infer<typeof insertPostLikeSchema>;
export type InsertPostComment = z.infer<typeof insertPostCommentSchema>;
export type InsertFollow = z.infer<typeof insertFollowSchema>;
export type Story = typeof storiesTable.$inferSelect;
export type FeedPost = typeof feedPostsTable.$inferSelect;
export type PostLike = typeof postLikesTable.$inferSelect;
export type PostComment = typeof postCommentsTable.$inferSelect;
export type Follow = typeof followsTable.$inferSelect;
