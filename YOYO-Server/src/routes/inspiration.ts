/**
 * /api/inspiration 与 /api/inspiration/image。
 *
 * 修复要点：
 * - A-04：流程变为「预扣 → AI 成功保留 → AI 失败 refund」。避免并发把余额扣穿。
 * - A-21：进入路由先按 userId 走 5/min 限流，超额 429。
 * - A-07：用 `withAuth` 收掉鉴权样板。
 * - A-13：所有读 `users` 加 `deleted_at IS NULL`。
 */

import { CreditService } from "../credits";
import { withAuth, authErrorResponse } from "../lib/auth";
import { consumeRateLimit } from "../lib/rate_limit";
import { generateInspirations, generateInspirationImage } from "../inspiration";

interface InspirationRequest {
  imageBase64: string;
  mimeType: string;
  language: string;
}

interface InspirationImageRequest {
  imageBase64: string;
  mimeType: string;
  imageGenPrompt: string;
}

/**
 * Pro 检查 + 限流 + 预扣（A-04）共用的「前置」，返回 ok 或已经写好的 Response。
 *
 * 把这段抽出来是因为三个 AI 端点（`/api/inspiration`、`/api/inspiration/image`、
 * `/api/ai_darkroom/process`）走的都是同一套：必须是 Pro、有积分、5/min、按原子预扣。
 */
async function preflightAi(
  userId: number,
  env: Env,
  bucket: string
): Promise<
  | { ok: true; service: CreditService; rate: { remaining: number; resetMs: number } }
  | { ok: false; response: Response }
> {
  const user = await env.DB.prepare(
    "SELECT subscription_status, subscription_end_date FROM users " +
      "WHERE id = ? AND deleted_at IS NULL"
  )
    .bind(userId)
    .first<{ subscription_status: number; subscription_end_date: string | null }>();

  if (!user) {
    return { ok: false, response: authErrorResponse(401, "User not found") };
  }

  // Pro 校验：subscription_status=1 且未过期。
  let isPro = user.subscription_status === 1;
  if (isPro && user.subscription_end_date) {
    if (new Date(user.subscription_end_date).getTime() < Date.now()) {
      isPro = false;
    }
  }
  if (!isPro) {
    return {
      ok: false,
      response: authErrorResponse(403, "Pro membership required", {
        // 与原版兼容：error body 里继续带 status
      }),
    };
  }

  // 限流（A-21）：5/min per user per bucket。
  const rate = await consumeRateLimit(env.DB, userId, bucket);
  if (!rate.allowed) {
    return {
      ok: false,
      response: new Response(
        JSON.stringify({
          error: "Rate limit exceeded",
          resetMs: rate.resetMs,
          bucket,
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
      ),
    };
  }

  // 原子预扣（A-04）：SQL 本身保证并发安全。
  const service = new CreditService(env);
  try {
    await service.deductCredits(userId, 1);
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    return {
      ok: false,
      response: authErrorResponse(403, "Insufficient credits"),
    };
  }
  return { ok: true, service, rate };
}

/** POST /api/inspiration。 */
export const postInspiration = withAuth(async (userId, request, env) => {
  const pre = await preflightAi(userId, env, "inspiration");
  if (!pre.ok) return pre.response;

  let body: InspirationRequest;
  try {
    body = (await request.json()) as InspirationRequest;
  } catch {
    await pre.service.refundCredits(userId, 1);
    return authErrorResponse(400, "Invalid JSON body");
  }
  const { imageBase64, mimeType, language } = body;

  if (!imageBase64 || !mimeType) {
    await pre.service.refundCredits(userId, 1);
    return authErrorResponse(400, "Missing imageBase64 or mimeType");
  }

  if (imageBase64.length > 10 * 1024 * 1024) {
    await pre.service.refundCredits(userId, 1);
    return authErrorResponse(413, "Image too large");
  }

  try {
    const result = await generateInspirations(
      imageBase64,
      mimeType,
      language || "en",
      env.GEMINI_API_KEY,
      env
    );
    const credits = await pre.service.getUserCredits(userId);
    return Response.json({ ...result, credits: credits?.credits ?? 0 });
  } catch (error) {
    // A-04：AI 失败回补。
    await pre.service.refundCredits(userId, 1);
    console.error("Inspiration error:", error);
    return authErrorResponse(500, "Failed to generate inspirations");
  }
});

/** POST /api/inspiration/image。 */
export const postInspirationImage = withAuth(async (userId, request, env) => {
  const pre = await preflightAi(userId, env, "inspiration_image");
  if (!pre.ok) return pre.response;

  let body: InspirationImageRequest;
  try {
    body = (await request.json()) as InspirationImageRequest;
  } catch {
    await pre.service.refundCredits(userId, 1);
    return authErrorResponse(400, "Invalid JSON body");
  }
  const { imageBase64, mimeType, imageGenPrompt } = body;

  if (!imageBase64 || !mimeType || !imageGenPrompt) {
    await pre.service.refundCredits(userId, 1);
    return authErrorResponse(400, "Missing required fields");
  }

  if (imageBase64.length > 10 * 1024 * 1024) {
    await pre.service.refundCredits(userId, 1);
    return authErrorResponse(413, "Image too large");
  }

  try {
    const result = await generateInspirationImage(
      imageBase64,
      mimeType,
      imageGenPrompt,
      env.GEMINI_API_KEY,
      env
    );
    const credits = await pre.service.getUserCredits(userId);
    return Response.json({ ...result, credits: credits?.credits ?? 0 });
  } catch (error) {
    await pre.service.refundCredits(userId, 1);
    console.error("Inspiration image generation error:", error);
    return authErrorResponse(500, "Failed to generate inspiration image");
  }
});
