/**
 * /api/user 路由：GET / PUT / DELETE。
 *
 * 修复要点：
 * - A-07：用 `withAuth` 收掉重复鉴权样板。
 * - A-13：所有读 `users` 的查询带 `AND deleted_at IS NULL`（软删除用户视为不存在）。
 */

import { withAuth, authErrorResponse } from "../lib/auth";
import { DEFAULT_FREE_CREDITS } from "../credits";

interface UserRecord {
  id: number;
  apple_user_id: string;
  email: string | null;
  full_name: string | null;
  credits: number;
  subscription_status: number;
}

interface UserResponse {
  id: number;
  appleUserId: string;
  email: string | null;
  fullName: string | null;
  credits: number;
  subscriptionStatus: number; // 0: free, 1: pro
}

/** GET /api/user —— 拿当前用户资料。A-13：滤 deleted_at。 */
export const getUser = withAuth(async (userId, _request, env) => {
  const user = await env.DB.prepare(
    "SELECT id, apple_user_id, email, full_name, credits, subscription_status FROM users " +
      "WHERE id = ? AND deleted_at IS NULL"
  )
    .bind(userId)
    .first<UserRecord>();

  if (!user) {
    return authErrorResponse(404, "User not found");
  }

  const userResponse: UserResponse = {
    id: user.id,
    appleUserId: user.apple_user_id,
    email: user.email,
    fullName: user.full_name,
    credits: user.credits ?? DEFAULT_FREE_CREDITS,
    subscriptionStatus: user.subscription_status ?? 0,
  };

  return Response.json(userResponse);
});

/** PUT /api/user —— 改 fullName。 */
export const updateUser = withAuth(async (userId, request, env) => {
  let body: { fullName?: string };
  try {
    body = (await request.json()) as { fullName?: string };
  } catch {
    return authErrorResponse(400, "Invalid JSON body");
  }
  const { fullName } = body;

  if (!fullName || fullName.trim().length === 0) {
    return authErrorResponse(400, "Full name is required");
  }
  if (fullName.length > 30) {
    return authErrorResponse(400, "Full name is too long");
  }

  // A-13：必须确保用户没有被软删除；否则软删除用户被「复活」会导致意外状态。
  const updateResult = await env.DB.prepare(
    "UPDATE users SET full_name = ?, updated_at = datetime('now') " +
      "WHERE id = ? AND deleted_at IS NULL"
  )
    .bind(fullName.trim(), userId)
    .run();

  if (!updateResult.meta.changes) {
    return authErrorResponse(404, "User not found");
  }

  return Response.json({ fullName: fullName.trim() });
});

/** DELETE /api/user —— 软删除用户（A-13 必备路径）。 */
export const deleteUser = withAuth(async (userId, _request, env) => {
  // 先清掉 shared_automation_rules，再软删除。shared_automation_rules.user_id 上有
  // ON DELETE CASCADE，但软删除不会触发，所以要显式 DELETE。
  await env.DB.batch([
    env.DB.prepare("DELETE FROM shared_automation_rules WHERE user_id = ?").bind(userId),
    env.DB.prepare(
      "UPDATE users SET deleted_at = datetime('now'), email = NULL, full_name = NULL, " +
        "credits = 0, subscription_status = 0, updated_at = datetime('now') " +
        "WHERE id = ? AND deleted_at IS NULL"
    ).bind(userId),
  ]);

  return Response.json({ success: true });
});
