/**
 * 用户积分服务（修复 A-04 / A-13）。
 *
 * 关键修复
 * --------
 * - A-13：`getUserCredits` / `deductCredits` 之前**没有** `AND deleted_at IS NULL`
 *   过滤，软删除用户仍能被查到并继续扣积分。加上过滤、并保留 `deleted_at` 复活逻辑
 *   （在 `src/routes/auth.ts` 里通过 Apple Sign In 重登自动清 `deleted_at`）。
 *
 * - A-04：之前三条 AI 路径都是「读余额 → 调 AI → 减积分」，并发下会把积分扣穿
 *   （用户余额 1，发两个并发请求，两个都看到 1，都调 AI，**两个都扣 -1**，最后余额 -1）。
 *   修复方案是「先原子预扣（`deductCredits` 的 `UPDATE ... WHERE credits>=?` 本身就是
 *   原子的）→ AI 成功则保留；失败则 `refundCredits` 回补」。`refundCredits` 同样走
 *   原子 SQL（`UPDATE credits = credits + ?`），但用 `MAX` 上限软上限 10_000 防止异常
 *   状态把积分刷到天上。
 *
 * 设计取舍：`refundCredits` 上限 10_000 是历史单笔最大正累加（PRO 100/月 × 多年）、
 *   但不依赖 PRO 状态，因为它和 `deductCredits` 用同一张 users 表。任何超过 10k
 *   的回补都直接被截断，避免脏数据长期不见。
 */

export const PRO_MONTHLY_CREDITS = 100;
export const DEFAULT_FREE_CREDITS = 0;
/** 单次回补上限，防止异常路径无限堆积积。 */
export const MAX_REFUND_PER_CALL = 10_000;

export interface UserCredits {
  credits: number;
  subscriptionStatus: number; // 0: free, 1: pro
}

export class CreditService {
  private env: Env;

  constructor(env: Env) {
    this.env = env;
  }

  /**
   * 取当前积分与订阅状态。
   *
   * 一律过滤 `deleted_at IS NULL` —— 这是 A-13 的核心点：调用方拿到 `null` 就当
   * 「不存在」，绝不能让软删除用户的旧余额被新用户继承（竞态里被同时消耗）。
   */
  async getUserCredits(userId: number): Promise<UserCredits | null> {
    const user = await this.env.DB.prepare(
      "SELECT credits, subscription_status, subscription_end_date FROM users " +
        "WHERE id = ? AND deleted_at IS NULL"
    )
      .bind(userId)
      .first<{
        credits: number;
        subscription_status: number;
        subscription_end_date: string | null;
      }>();

    if (!user) {
      return null;
    }

    const credits = user.credits ?? DEFAULT_FREE_CREDITS;
    let status = user.subscription_status ?? 0;

    // 时间过期的订阅在读侧就地降级，避免脏的 pro 状态被下游误判。
    if (status === 1 && user.subscription_end_date) {
      const endDate = new Date(user.subscription_end_date);
      if (endDate.getTime() < Date.now()) {
        status = 0;
      }
    }

    return {
      credits,
      subscriptionStatus: status,
    };
  }

  /**
   * 原子预扣。
   *
   * 之所以是「预扣」而不是「扣减」：`UPDATE credits = credits - ? WHERE id = ?
   * AND credits >= ?` 在 D1 上是单条 SQL，Cold Start 间的并发执行也只有一个能成
   * 功 —— 这就把「读余额 → 减一」的 TOCTOU 收窄到数据库层面。
   *
   * 成功路径：调用方继续调 AI；AI 抛错时再走 `refundCredits` 回补。
   * 失败路径：余额不足，调用方应当把请求按 403/500 返回，**不要再回补**。
   */
  async deductCredits(userId: number, amount: number = 1): Promise<number> {
    if (!Number.isSafeInteger(amount) || amount <= 0) {
      throw new Error("Invalid credit amount");
    }
    const result = await this.env.DB.prepare(
      "UPDATE users SET credits = credits - ?, updated_at = datetime('now') " +
        "WHERE id = ? AND deleted_at IS NULL AND credits >= ? " +
        "RETURNING credits"
    )
      .bind(amount, userId, amount)
      .first<{ credits: number }>();

    if (!result) {
      // 要么用户不存在 / 软删除，要么余额不足 —— 两种都属于「不能再服务」，
      // 由调用方分类报错（前者 401，后者 403/402）。
      throw new Error("Insufficient credits or user not found");
    }
    return result.credits;
  }

  /**
   * 回补积分，用于 AI 失败 / 异常路径。
   *
   * 同样用单条 SQL 原子加，不能「先读后写」。返回加完之后的余额。
   * 上限 `MAX(0, ...)` 防御性限制单次回补，避免极端情况下积分被刷飞；
   * 同时 `MAX_REFUND_PER_CALL` 限制单次上限。
   */
  async refundCredits(userId: number, amount: number = 1): Promise<number> {
    if (!Number.isSafeInteger(amount) || amount <= 0) {
      return 0;
    }
    const capped = Math.min(amount, MAX_REFUND_PER_CALL);
    const result = await this.env.DB.prepare(
      "UPDATE users SET credits = credits + ?, updated_at = datetime('now') " +
        "WHERE id = ? AND deleted_at IS NULL " +
        "RETURNING credits"
    )
      .bind(capped, userId)
      .first<{ credits: number }>();

    if (!result) {
      // 用户不存在或已软删除，悄悄忽略：原先的扣减已是回不来，但也不应再传染更多状态。
      console.error("refundCredits: user gone", { userId });
      return 0;
    }
    return result.credits;
  }
}
