import { pgTable, uuid, varchar, text, boolean, timestamp, jsonb, decimal } from "drizzle-orm/pg-core";
import { createInsertSchema } from "drizzle-zod";
import { z } from "zod/v4";
import { usersTable } from "./users";

export const walletAccountsTable = pgTable("wallet_accounts", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id").references(() => usersTable.id).unique(),
  balance: decimal("balance", { precision: 15, scale: 2 }).default("0.00"),
  currency: varchar("currency", { length: 10 }).default("IDR"),
  isActive: boolean("is_active").default(true),
  pinHash: text("pin_hash"),
  createdAt: timestamp("created_at").defaultNow(),
});

export const walletTransactionsTable = pgTable("wallet_transactions", {
  id: uuid("id").primaryKey().defaultRandom(),
  walletId: uuid("wallet_id").references(() => walletAccountsTable.id),
  type: varchar("type", { length: 30 }).notNull(),
  amount: decimal("amount", { precision: 15, scale: 2 }).notNull(),
  fee: decimal("fee", { precision: 15, scale: 2 }).default("0.00"),
  description: text("description"),
  referenceId: text("reference_id"),
  counterpartyId: uuid("counterparty_id").references(() => usersTable.id),
  status: varchar("status", { length: 20 }).default("pending"),
  metadata: jsonb("metadata").default({}),
  createdAt: timestamp("created_at").defaultNow(),
});

export const insertWalletAccountSchema = createInsertSchema(walletAccountsTable).omit({ id: true, createdAt: true });
export const insertWalletTransactionSchema = createInsertSchema(walletTransactionsTable).omit({ id: true, createdAt: true });

export type InsertWalletAccount = z.infer<typeof insertWalletAccountSchema>;
export type InsertWalletTransaction = z.infer<typeof insertWalletTransactionSchema>;
export type WalletAccount = typeof walletAccountsTable.$inferSelect;
export type WalletTransaction = typeof walletTransactionsTable.$inferSelect;
