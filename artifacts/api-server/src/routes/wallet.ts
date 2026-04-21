import { Router } from "express";
import { db } from "@workspace/db";
import { walletAccountsTable, walletTransactionsTable } from "@workspace/db/schema";
import { eq, desc } from "drizzle-orm";
import { authenticate, AuthRequest } from "../middlewares/authenticate";
import { z } from "zod/v4";
import bcrypt from "bcryptjs";

const router = Router();
router.use(authenticate);

// GET /wallet
router.get("/", async (req: AuthRequest, res) => {
  try {
    let [wallet] = await db.select().from(walletAccountsTable).where(eq(walletAccountsTable.userId, req.userId!)).limit(1);
    if (!wallet) {
      const [created] = await db.insert(walletAccountsTable).values({ userId: req.userId }).returning();
      wallet = created;
    }
    res.json({ id: wallet.id, balance: wallet.balance, currency: wallet.currency, isActive: wallet.isActive });
  } catch (err) {
    req.log.error(err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// GET /wallet/transactions
router.get("/transactions", async (req: AuthRequest, res) => {
  try {
    const [wallet] = await db.select().from(walletAccountsTable).where(eq(walletAccountsTable.userId, req.userId!)).limit(1);
    if (!wallet) { res.json([]); return; }
    const transactions = await db.select().from(walletTransactionsTable)
      .where(eq(walletTransactionsTable.walletId, wallet.id))
      .orderBy(desc(walletTransactionsTable.createdAt))
      .limit(50);
    res.json(transactions);
  } catch (err) {
    req.log.error(err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// POST /wallet/topup
router.post("/topup", async (req: AuthRequest, res) => {
  try {
    const schema = z.object({
      amount: z.number().positive(),
      referenceId: z.string().optional(),
    });
    const parsed = schema.safeParse(req.body);
    if (!parsed.success) { res.status(400).json({ error: "Validation failed" }); return; }

    let [wallet] = await db.select().from(walletAccountsTable).where(eq(walletAccountsTable.userId, req.userId!)).limit(1);
    if (!wallet) {
      const [created] = await db.insert(walletAccountsTable).values({ userId: req.userId }).returning();
      wallet = created;
    }

    const newBalance = (parseFloat(wallet.balance || "0") + parsed.data.amount).toFixed(2);
    await db.update(walletAccountsTable).set({ balance: newBalance }).where(eq(walletAccountsTable.id, wallet.id));

    const [tx] = await db.insert(walletTransactionsTable).values({
      walletId: wallet.id,
      type: "topup",
      amount: parsed.data.amount.toFixed(2),
      description: "Top up",
      referenceId: parsed.data.referenceId,
      status: "success",
    }).returning();

    res.status(201).json({ transaction: tx, newBalance });
  } catch (err) {
    req.log.error(err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// POST /wallet/transfer
router.post("/transfer", async (req: AuthRequest, res) => {
  try {
    const schema = z.object({
      toUserId: z.string(),
      amount: z.number().positive(),
      description: z.string().optional(),
    });
    const parsed = schema.safeParse(req.body);
    if (!parsed.success) { res.status(400).json({ error: "Validation failed" }); return; }

    const [senderWallet] = await db.select().from(walletAccountsTable).where(eq(walletAccountsTable.userId, req.userId!)).limit(1);
    if (!senderWallet || parseFloat(senderWallet.balance || "0") < parsed.data.amount) {
      res.status(400).json({ error: "Insufficient balance" });
      return;
    }

    let [receiverWallet] = await db.select().from(walletAccountsTable).where(eq(walletAccountsTable.userId, parsed.data.toUserId)).limit(1);
    if (!receiverWallet) {
      const [created] = await db.insert(walletAccountsTable).values({ userId: parsed.data.toUserId }).returning();
      receiverWallet = created;
    }

    const senderNewBal = (parseFloat(senderWallet.balance || "0") - parsed.data.amount).toFixed(2);
    const receiverNewBal = (parseFloat(receiverWallet.balance || "0") + parsed.data.amount).toFixed(2);

    await db.update(walletAccountsTable).set({ balance: senderNewBal }).where(eq(walletAccountsTable.id, senderWallet.id));
    await db.update(walletAccountsTable).set({ balance: receiverNewBal }).where(eq(walletAccountsTable.id, receiverWallet.id));

    await db.insert(walletTransactionsTable).values({
      walletId: senderWallet.id,
      type: "transfer_out",
      amount: parsed.data.amount.toFixed(2),
      description: parsed.data.description || "Transfer",
      counterpartyId: parsed.data.toUserId,
      status: "success",
    });
    await db.insert(walletTransactionsTable).values({
      walletId: receiverWallet.id,
      type: "transfer_in",
      amount: parsed.data.amount.toFixed(2),
      description: parsed.data.description || "Transfer",
      counterpartyId: req.userId,
      status: "success",
    });

    res.json({ success: true, newBalance: senderNewBal });
  } catch (err) {
    req.log.error(err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// POST /wallet/pin
router.post("/pin", async (req: AuthRequest, res) => {
  try {
    const schema = z.object({ pin: z.string().length(6) });
    const parsed = schema.safeParse(req.body);
    if (!parsed.success) { res.status(400).json({ error: "PIN must be 6 digits" }); return; }
    const pinHash = await bcrypt.hash(parsed.data.pin, 10);
    await db.update(walletAccountsTable).set({ pinHash }).where(eq(walletAccountsTable.userId, req.userId!));
    res.json({ message: "PIN set" });
  } catch (err) {
    req.log.error(err);
    res.status(500).json({ error: "Internal server error" });
  }
});

export default router;
