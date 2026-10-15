/**
 * POST /api/auth/apple —— Apple Sign In。
 *
 * 修复要点：
 * - A-06：`verifyAppleIdentityToken(..., env.APP_STORE_BUNDLE_ID)` 校验 aud。
 * - A-13：用户表查询 `apple_user_id = ?` 的旧路径通过「auth 登录」路径复活
 *   （`UPDATE users ... deleted_at = NULL ...`），保持原行为不变；其它位置
 *   仍然用 `deleted_at IS NULL` 过滤。
 */

import jwt from "@tsndr/cloudflare-worker-jwt";
import { verifyAppleIdentityToken } from "../auth/apple";
import { DEFAULT_FREE_CREDITS } from "../credits";
import { authErrorResponse } from "../lib/auth";

interface AuthRequest {
  identityToken: string;
  userIdentifier: string;
  fullName?: string;
  email?: string;
}

interface User {
  id: number;
  appleUserId: string;
  email: string | null;
  fullName: string | null;
  credits: number;
  subscriptionStatus: number; // 0: free, 1: pro
}

export async function handleAppleAuth(request: Request, env: Env): Promise<Response> {
  let body: AuthRequest;
  try {
    body = (await request.json()) as AuthRequest;
  } catch {
    return authErrorResponse(400, "Invalid JSON body");
  }
  const { identityToken, userIdentifier, fullName, email } = body;

  if (!identityToken || !userIdentifier) {
    return authErrorResponse(400, "Missing identityToken or userIdentifier");
  }

  // A-06：第三个参数 expectedAudience 从 env 拿，与 iOS App 的 bundle id 对齐。
  const expectedAudience = env.APP_STORE_BUNDLE_ID;
  if (!expectedAudience) {
    console.error("APP_STORE_BUNDLE_ID not configured");
    return authErrorResponse(500, "Internal server error");
  }

  const isValid = await verifyAppleIdentityToken(identityToken, userIdentifier, expectedAudience);
  if (!isValid) {
    return authErrorResponse(401, "Invalid identity token");
  }

  // 现有用户则保留并刷新（A-13 复活路径）。
  const existingUser = await env.DB.prepare(
    "SELECT id, apple_user_id, email, full_name, credits, subscription_status FROM users " +
      "WHERE apple_user_id = ?"
  )
    .bind(userIdentifier)
    .first<{
      id: number;
      apple_user_id: string;
      email: string | null;
      full_name: string | null;
      credits: number;
      subscription_status: number;
    }>();

  let user: User;

  if (existingUser) {
    // 重登时清 deleted_at —— 这是 A-13 复活软删除用户的合法路径，与 A-13 的
    // 「其它路径必须过滤 deleted_at」并不冲突。
    await env.DB.prepare(
      "UPDATE users SET full_name = COALESCE(?, full_name), email = COALESCE(?, email), " +
        "deleted_at = NULL, updated_at = datetime('now') WHERE apple_user_id = ?"
    )
      .bind(fullName || null, email || null, userIdentifier)
      .run();

    user = {
      id: existingUser.id,
      appleUserId: existingUser.apple_user_id,
      email: email || existingUser.email,
      fullName: fullName || existingUser.full_name,
      credits: existingUser.credits ?? DEFAULT_FREE_CREDITS,
      subscriptionStatus: existingUser.subscription_status ?? 0,
    };
  } else {
    const result = await env.DB.prepare(
      `INSERT INTO users (apple_user_id, email, full_name, credits, subscription_status) ` +
        `VALUES (?, ?, ?, ?, 0)`
    )
      .bind(userIdentifier, email || null, fullName || null, DEFAULT_FREE_CREDITS)
      .run();

    user = {
      id: result.meta.last_row_id as number,
      appleUserId: userIdentifier,
      email: email || null,
      fullName: fullName || null,
      credits: DEFAULT_FREE_CREDITS,
      subscriptionStatus: 0,
    };
  }

  const token = await jwt.sign(
    {
      id: user.id,
      exp: Math.floor(Date.now() / 1000) + 7 * 24 * 60 * 60, // 7 days
    },
    env.JWT_SECRET
  );

  return Response.json({ user, token });
}
