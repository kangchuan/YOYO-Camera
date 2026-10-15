/**
 * POST /api/user/subscribe —— IAP 订阅。
 *
 * 行为基本与原 `src/index.ts:351-567` 一致（保留原 URL / 响应 / 状态码），但：
 * - A-07：用 `withAuth` 收掉鉴权。
 * - A-22：catch 块不再把 `error.message` 返回给客户端（详情进 console.error）。
 * - A-13：`UPDATE users WHERE id = ?` 加上 `AND deleted_at IS NULL`。
 */

import { PRO_MONTHLY_CREDITS } from "../credits";
import { withAuth, authErrorResponse } from "../lib/auth";
import { validateAppleSubscription } from "../iap";

export const subscribe = withAuth(async (userId, request, env) => {
  let body: { originalTransactionId: string };
  try {
    body = (await request.json()) as { originalTransactionId: string };
  } catch {
    return authErrorResponse(400, "Invalid JSON body");
  }
  const { originalTransactionId } = body;

  if (!originalTransactionId) {
    return authErrorResponse(400, "Missing originalTransactionId");
  }

  // 同一笔 transactionId 不能绑到另一个 user。
  const boundUser = await env.DB.prepare(
    "SELECT id FROM users WHERE original_transaction_id = ? AND deleted_at IS NULL"
  )
    .bind(originalTransactionId)
    .first<{ id: number }>();

  if (boundUser && boundUser.id !== userId) {
    return authErrorResponse(409, "This subscription is already bound to another account.");
  }

  const validationResult = await validateAppleSubscription(originalTransactionId, env);

  if (!validationResult.isValid) {
    return authErrorResponse(400, "Invalid subscription or verification failed");
  }

  // 续期 / 新订阅：用 last_transaction_id 去重，避免 webhook + 主动续订双发。
  const status = validationResult.isPro ? 1 : 0;
  const endDate = validationResult.expiresDateMs
    ? new Date(validationResult.expiresDateMs).toISOString()
    : null;

  let finalCredits: number | null = null;

  if (status === 1) {
    const transactionId = validationResult.transactionId;
    if (transactionId) {
      // Only award credits if this transaction is new to the user (idempotent).
      const result = await env.DB.prepare(
        "UPDATE users SET subscription_status = ?, subscription_end_date = ?, " +
          "updated_at = datetime('now'), original_transaction_id = ?, " +
          "credits = credits + ?, last_transaction_id = ? " +
          "WHERE id = ? AND deleted_at IS NULL AND " +
          "(last_transaction_id IS NULL OR last_transaction_id != ?) " +
          "RETURNING credits"
      )
        .bind(
          status,
          endDate,
          originalTransactionId,
          PRO_MONTHLY_CREDITS,
          transactionId,
          userId,
          transactionId
        )
        .first<{ credits: number }>();

      if (result) {
        finalCredits = result.credits;
      } else {
        // 已经处理过同一笔 transaction，仅刷新状态、不再加积分。
        const updateResult = await env.DB.prepare(
          "UPDATE users SET subscription_status = ?, subscription_end_date = ?, " +
            "updated_at = datetime('now'), original_transaction_id = ? " +
            "WHERE id = ? AND deleted_at IS NULL " +
            "RETURNING credits"
        )
          .bind(status, endDate, originalTransactionId, userId)
          .first<{ credits: number }>();
        finalCredits = updateResult?.credits ?? 0;
      }
    }
  } else if (validationResult.cancellationDateMs) {
    // 退款：把当年奖励的积分扣回（clamp 到 0）。
    const result = await env.DB.prepare(
      "UPDATE users SET subscription_status = ?, subscription_end_date = ?, " +
        "updated_at = datetime('now'), original_transaction_id = ?, " +
        "credits = MAX(0, credits - ?) " +
        "WHERE id = ? AND deleted_at IS NULL " +
        "RETURNING credits"
    )
      .bind(status, endDate, originalTransactionId, PRO_MONTHLY_CREDITS, userId)
      .first<{ credits: number }>();
    finalCredits = result?.credits ?? 0;
  } else {
    // 自然过期：只刷状态、积分不动。
    const result = await env.DB.prepare(
      "UPDATE users SET subscription_status = ?, subscription_end_date = ?, " +
        "updated_at = datetime('now'), original_transaction_id = ? " +
        "WHERE id = ? AND deleted_at IS NULL " +
        "RETURNING credits"
    )
      .bind(status, endDate, originalTransactionId, userId)
      .first<{ credits: number }>();
    finalCredits = result?.credits ?? 0;
  }

  return Response.json({
    subscriptionStatus: status,
    subscriptionEndDate: endDate,
    credits: finalCredits,
  });
});
