/**
 * POST /api/ai_darkroom/process —— AI 修图。
 *
 * 修复要点同 `src/routes/inspiration.ts`：
 * - A-04：原子预扣 + 失败 refund
 * - A-21：5/min 限流
 * - A-07：withAuth
 * - A-13：deleted_at IS NULL
 */

import { CreditService } from "../credits";
import { withAuth, authErrorResponse } from "../lib/auth";
import { consumeRateLimit } from "../lib/rate_limit";
import { processAIDarkroomRequest } from "../ai_darkroom";

export const postAIDarkroom = withAuth(async (userId, request, env) => {
  // Pro 校验 + 限流 + 预扣
  const user = await env.DB.prepare(
    "SELECT subscription_status, subscription_end_date FROM users " +
      "WHERE id = ? AND deleted_at IS NULL"
  )
    .bind(userId)
    .first<{ subscription_status: number; subscription_end_date: string | null }>();

  if (!user) {
    return authErrorResponse(401, "User not found");
  }

  let isPro = user.subscription_status === 1;
  if (isPro && user.subscription_end_date) {
    if (new Date(user.subscription_end_date).getTime() < Date.now()) {
      isPro = false;
    }
  }
  if (!isPro) {
    return authErrorResponse(403, "Pro membership required");
  }

  const rate = await consumeRateLimit(env.DB, userId, "ai_darkroom");
  if (!rate.allowed) {
    return new Response(
      JSON.stringify({
        error: "Rate limit exceeded",
        resetMs: rate.resetMs,
        bucket: "ai_darkroom",
      }),
      {
        status: 429,
        headers: {
          "Content-Type": "application/json",
          "Retry-After": `${Math.ceil(rate.resetMs / 1000)}`,
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "GET, POST, DELETE, PUT, OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type, Authorization",
        },
      }
    );
  }

  // A-04：原子预扣。
  const service = new CreditService(env);
  try {
    await service.deductCredits(userId, 1);
  } catch (e) {
    console.error("deductCredits failed:", e);
    return authErrorResponse(403, "Insufficient credits");
  }

  let body: any;
  try {
    body = await request.json();
  } catch {
    await service.refundCredits(userId, 1);
    return authErrorResponse(400, "Invalid JSON body");
  }
  const { imageBase64, mimeType, operation, options } = body;

  if (!imageBase64 || !mimeType || !operation) {
    await service.refundCredits(userId, 1);
    return authErrorResponse(400, "Missing required fields");
  }

  try {
    const result = await processAIDarkroomRequest(
      imageBase64,
      mimeType,
      operation,
      options,
      env.GEMINI_API_KEY,
      env
    );
    const credits = await service.getUserCredits(userId);
    return Response.json({ ...result, credits: credits?.credits ?? 0 });
  } catch (error) {
    // A-04：AI 失败回补。
    await service.refundCredits(userId, 1);
    console.error("AI Darkroom error:", error);
    return authErrorResponse(500, "Failed to process AI Darkroom request");
  }
});
