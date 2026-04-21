import { Router, type IRouter } from "express";
import healthRouter from "./health";
import authRouter from "./auth";
import chatRouter from "./chat";
import feedRouter from "./feed";
import emailRouter from "./email";
import communityRouter from "./community";
import walletRouter from "./wallet";
import notificationsRouter from "./notifications";
import storageRouter from "./storage";
import usersRouter from "./users";

const router: IRouter = Router();

router.use(healthRouter);
router.use("/auth", authRouter);
router.use("/chat", chatRouter);
router.use("/feed", feedRouter);
router.use("/email", emailRouter);
router.use("/community", communityRouter);
router.use("/wallet", walletRouter);
router.use("/notifications", notificationsRouter);
router.use("/storage", storageRouter);
router.use("/users", usersRouter);

export default router;
