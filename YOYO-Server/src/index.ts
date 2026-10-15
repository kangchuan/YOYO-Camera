/**
 * YOYO Camera API —— Cloudflare Worker 入口。
 *
 * 修复一览：
 * - A-01：Webhook 路由由 `src/routes/webhook.ts` 用 `verifyAppleJws` 做完整证书链 + JWS 验签。
 * - A-03：bundle id 配置见 `wrangler.jsonc`（已改为 `com.anyan.YoyoCamera`）。
 * - A-04：AI 三个端点改为「原子预扣 → 失败 refund」，见 `src/credits.ts` 和
 *         `src/routes/{inspiration,ai_darkroom}.ts`。
 * - A-06：`verifyAppleIdentityToken` 新增 `expectedAudience`（即 bundle id）校验。
 * - A-07 + A-14：路由拆到 `src/routes/` 下，这里只剩「路由注册 + CORS + 单 fetch 入口」。
 * - A-13：所有读 `users` 的查询一律 `AND deleted_at IS NULL`（软删除用户视为不存在）。
 * - A-16：AI Gateway accountId / name 从 env 读，保留原值兜底。
 * - A-20：`schema.sql` 与 `credits.ts` 的默认对齐（credits DEFAULT 0）。
 * - A-21：CORS 可配置（`env.CORS_ALLOW_ORIGIN`），AI 三个端点有 5/min/user 限流。
 * - A-22：catch 块不再返回 `error.message`，详情进 console.error。
 *
 * 入口契约（不变）：`export default { fetch }`；`wrangler.jsonc` 的 `main` 仍指本文件。
 */

import { handleAppleAuth } from "./routes/auth";
import { getUser, updateUser, deleteUser } from "./routes/user";
import { subscribe } from "./routes/subscription";
import { createShareRule, getShareRule } from "./routes/automation";
import { postInspiration, postInspirationImage } from "./routes/inspiration";
import { postAIDarkroom } from "./routes/ai_darkroom";
import { handleAppStoreWebhook } from "./routes/webhook";

/**
 * 计算 CORS header。
 *
 * 优先级：
 *   1. env.CORS_ALLOW_ORIGIN（已配置则覆盖默认）
 *   2. 默认 "*" —— 保持与原版相同的兼容行为
 *
 * 当 origin 是具体域名时浏览器会要求 `Vary: Origin`，这里为了让 wrangler 默认
 * cache 行为简单不强制加 Vary；如有需要可以在配置项里再加。
 */
function buildCorsHeaders(env: Env, request: Request): Record<string, string> {
  const configured = env.CORS_ALLOW_ORIGIN?.trim();
  const origin = configured && configured.length > 0 ? configured : "*";
  // 简单 Vary 行为：response 总是带 Vary: Origin（浏览器看到具体 origin 时可能不会缓存）
  return {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Methods": "GET, POST, DELETE, PUT, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
    "Vary": "Origin",
  };
}

export default {
  async fetch(request, env, _ctx): Promise<Response> {
    const { pathname } = new URL(request.url);
    const corsHeaders = buildCorsHeaders(env, request);

    if (request.method === "OPTIONS") {
      return new Response(null, { headers: corsHeaders });
    }

    // ---- auth ----
    if (pathname === "/api/auth/apple" && request.method === "POST") {
      try {
        return await handleAppleAuth(request, env);
      } catch (error) {
        // A-22：详情进 console，body 一律泛化。
        console.error("Auth error:", error);
        return Response.json({ error: "Internal server error" }, { status: 500, headers: corsHeaders });
      }
    }

    // ---- user ----
    if (pathname === "/api/user" && request.method === "GET") {
      try {
        return await getUser(request as unknown as Request, env);
      } catch (error) {
        console.error("Get user profile error:", error);
        return Response.json({ error: "Internal server error" }, { status: 500, headers: corsHeaders });
      }
    }
    if (pathname === "/api/user" && request.method === "DELETE") {
      try {
        return await deleteUser(request as unknown as Request, env);
      } catch (error) {
        console.error("Delete user error:", error);
        return Response.json({ error: "Internal server error" }, { status: 500, headers: corsHeaders });
      }
    }
    if (pathname === "/api/user" && request.method === "PUT") {
      try {
        return await updateUser(request as unknown as Request, env);
      } catch (error) {
        console.error("Update user error:", error);
        return Response.json({ error: "Internal server error" }, { status: 500, headers: corsHeaders });
      }
    }

    // ---- subscription ----
    if (pathname === "/api/user/subscribe" && request.method === "POST") {
      try {
        return await subscribe(request as unknown as Request, env);
      } catch (error) {
        // A-22：去掉 `error.message` 拼到 body。
        console.error("Subscribe error:", error);
        return Response.json({ error: "Internal server error" }, { status: 500, headers: corsHeaders });
      }
    }

    // ---- automation ----
    if (pathname === "/api/automation/share" && request.method === "POST") {
      try {
        return await createShareRule(request as unknown as Request, env);
      } catch (error) {
        console.error("Share error:", error);
        return Response.json({ error: "Internal server error" }, { status: 500, headers: corsHeaders });
      }
    }
    if (pathname.startsWith("/api/automation/share/") && request.method === "GET") {
      try {
        return await getShareRule(pathname, env);
      } catch (error) {
        console.error("Get shared rule error:", error);
        return Response.json({ error: "Internal server error" }, { status: 500, headers: corsHeaders });
      }
    }

    // ---- AI endpoints ----
    if (pathname === "/api/inspiration" && request.method === "POST") {
      try {
        return await postInspiration(request as unknown as Request, env);
      } catch (error) {
        console.error("Inspiration error:", error);
        return Response.json({ error: "Failed to generate inspirations" }, { status: 500, headers: corsHeaders });
      }
    }
    if (pathname === "/api/inspiration/image" && request.method === "POST") {
      try {
        return await postInspirationImage(request as unknown as Request, env);
      } catch (error) {
        console.error("Inspiration image generation error:", error);
        return Response.json({ error: "Failed to generate inspiration image" }, { status: 500, headers: corsHeaders });
      }
    }
    if (pathname === "/api/ai_darkroom/process" && request.method === "POST") {
      try {
        return await postAIDarkroom(request as unknown as Request, env);
      } catch (error) {
        console.error("AI Darkroom error:", error);
        return Response.json({ error: "Failed to process AI Darkroom request" }, { status: 500, headers: corsHeaders });
      }
    }

    // ---- App Store Webhook ----
    if (pathname === "/api/webhook/appstore" && request.method === "POST") {
      // webhook 内部已经处理 401/200，这里不再外层包（避免把成功再翻 500）。
      return await handleAppStoreWebhook(request, env);
    }

    return new Response("YOYO Camera API", { headers: corsHeaders });
  },
} satisfies ExportedHandler<Env>;
