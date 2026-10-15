/**
 * POST /api/webhook/appstore —— App Store Server Notifications V2。
 *
 * A-01 修复点：之前的实现用 `jwt.decode(signedPayload)` 就信任 payload —— 任何人
 * POST 一个自造的 JSON 都能把任意账号刷成 PRO 或拿到积分。
 *
 * 现在：先走 `verifyAppleJws`（x5c 证书链 → 信任锚（Apple Root CA - G3）→ JWS 签名），
 * 失败一律返回 **401**（**不**是 500，避免暴露内部错误；**不**是 200，不让无效请求穿过）。
 *
 * 已知残余风险（已在 `src/appstore/jws.ts` 文档里展开）：
 * - 未做证书吊销检查（CRL/OCSP）。Apple 的中间证书被提前吊销时，本实现会继续接受。
 * - 未校验 keyUsage / extendedKeyUsage 等 X.509 扩展。
 *
 * URL 与成功响应（"OK" 200）保持与原版一致 —— iOS App Store 在校验失败时
 * 应收到 4xx，以触发重试，但 5xx 重复到一定次数 Apple 也会停止投递。这个
 * 折中可接受。
 */

import { PRO_MONTHLY_CREDITS } from "../credits";
import { verifyAppleJws, resolveTrustedRoots } from "../appstore/jws";

/** 与原版一致：返回 200 + "OK"，让 Apple 知道我们收到了通知。 */
function okResponse(): Response {
  return new Response("OK", { status: 200 });
}

/** 与原版一致：Apple webhook 不应回 401 的明文错误，回 401 是为了阻断伪造。 */
function unauthorized(message: string): Response {
  return new Response(message, { status: 401 });
}

export async function handleAppStoreWebhook(
  request: Request,
  env: Env
): Promise<Response> {
  // 读 body 一次，免得被多次 .json() 卡住。
  let body: any;
  try {
    body = await request.json();
  } catch {
    return unauthorized("Invalid JSON body");
  }

  const signedPayload = body?.signedPayload;
  if (typeof signedPayload !== "string" || signedPayload.length === 0) {
    return unauthorized("Missing signedPayload");
  }

  // A-01：从 env 取信任锚（默认 Apple Root CA - G3），完整校验 JWS。
  let trustedRoots: string[];
  let payload: any;
  try {
    trustedRoots = resolveTrustedRoots(env.APPLE_ROOT_CA_SHA256);
    const verified = await verifyAppleJws(signedPayload, { trustedRootFingerprints: trustedRoots });
    payload = verified.payload;
  } catch (e) {
    // A-01：验签失败一律 401，**不再** return 200，也**不**回 500。
    console.error("[Webhook] JWS verification failed:", e instanceof Error ? e.message : e);
    return unauthorized("Invalid JWS");
  }

  const notificationType = payload.notificationType;
  const subtype = payload.subtype;

  // 业务逻辑完全与原版一致；只把读 signedPayload 的部分换成验签过的 payload。
  if (!payload.data?.signedTransactionInfo) {
    return okResponse();
  }

  const signedTx = payload.data.signedTransactionInfo;
  let txPayload: any;
  try {
    // 内层 signedTransactionInfo 也需要验证（如果有 x5c，就一并验签）；
    // 这里是 Apple 自家对象、必带 x5c。沿用同一组 trust anchor。
    const verified = await verifyAppleJws(signedTx, { trustedRootFingerprints: trustedRoots });
    txPayload = verified.payload;
  } catch (e) {
    console.error("[Webhook] signedTransactionInfo verification failed:", e instanceof Error ? e.message : e);
    return unauthorized("Invalid signedTransactionInfo");
  }

  const originalTransactionId = txPayload.originalTransactionId;
  const transactionId = txPayload.transactionId;
  const expiresDateMs = parseInt(txPayload.expiresDate, 10);
  const revocationDateMs = txPayload.revocationDate
    ? parseInt(txPayload.revocationDate, 10)
    : undefined;

  console.error(`[Webhook] notification=${notificationType}/${subtype ?? ""} tx=${originalTransactionId} exp=${expiresDateMs}`);

  const user = await env.DB.prepare(
    "SELECT id, credits, last_transaction_id FROM users " +
      "WHERE original_transaction_id = ? AND deleted_at IS NULL"
  )
    .bind(originalTransactionId)
    .first<{ id: number; credits: number; last_transaction_id: string }>();

  if (!user) {
    console.error(`[Webhook] No user for originalTransactionId: ${originalTransactionId}`);
    return okResponse();
  }

  const nowMs = Date.now();
  const status = expiresDateMs > nowMs && !revocationDateMs ? 1 : 0;
  const endDate = new Date(expiresDateMs).toISOString();

  if (status === 1) {
    const result = await env.DB.prepare(
      "UPDATE users SET subscription_status = ?, subscription_end_date = ?, " +
        "updated_at = datetime('now'), credits = credits + ?, last_transaction_id = ? " +
        "WHERE id = ? AND deleted_at IS NULL AND " +
        "(last_transaction_id IS NULL OR last_transaction_id != ?)"
    )
      .bind(status, endDate, PRO_MONTHLY_CREDITS, transactionId, user.id, transactionId)
      .run();

    if (result.meta.changes === 0) {
      await env.DB.prepare(
        "UPDATE users SET subscription_status = ?, subscription_end_date = ?, " +
          "updated_at = datetime('now') WHERE id = ? AND deleted_at IS NULL"
      )
        .bind(status, endDate, user.id)
        .run();
      console.error(`[Webhook] User ${user.id} refreshed (no new credits).`);
    } else {
      console.error(`[Webhook] Renewal processed for user ${user.id}.`);
    }
  } else if (revocationDateMs) {
    await env.DB.prepare(
      "UPDATE users SET subscription_status = ?, subscription_end_date = ?, " +
        "updated_at = datetime('now'), credits = MAX(0, credits - ?) " +
        "WHERE id = ? AND deleted_at IS NULL"
    )
      .bind(status, endDate, PRO_MONTHLY_CREDITS, user.id)
      .run();
    console.error(`[Webhook] Revocation for user ${user.id}.`);
  } else {
    await env.DB.prepare(
      "UPDATE users SET subscription_status = ?, subscription_end_date = ?, " +
        "updated_at = datetime('now') WHERE id = ? AND deleted_at IS NULL"
    )
      .bind(status, endDate, user.id)
      .run();
  }

  return okResponse();
}
