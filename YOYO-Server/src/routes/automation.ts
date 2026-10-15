/**
 * /api/automation/share —— 创建 / 读取共享自动化规则。
 *
 * 修复要点：
 * - A-07：把鉴权收敛到 `withAuth`。
 * - A-13：用户表查询补 `deleted_at IS NULL`（虽然 share 不动 credits，但
 *   拿到已经被软删除的用户就会绕过删除，保护性补上）。
 */

import { generateShareCode } from "../share_code";
import { withAuth, authErrorResponse } from "../lib/auth";

interface ShareRequest {
  ruleJson: string;
}

/** POST /api/automation/share —— 创建共享码。 */
export const createShareRule = withAuth(async (userId, request, env) => {
  let body: ShareRequest;
  try {
    body = (await request.json()) as ShareRequest;
  } catch {
    return authErrorResponse(400, "Invalid JSON body");
  }
  const { ruleJson } = body;

  if (!ruleJson) {
    return authErrorResponse(400, "Missing ruleJson");
  }

  // 20KB 上限
  if (ruleJson.length > 20480) {
    return authErrorResponse(413, "Payload too large");
  }

  // A-13：用户必须存在且未被软删除。
  const user = await env.DB.prepare(
    "SELECT id FROM users WHERE id = ? AND deleted_at IS NULL"
  )
    .bind(userId)
    .first();

  if (!user) {
    return authErrorResponse(401, "User not found");
  }

  const maxRetries = 7;
  let code = "";
  for (let attempt = 0; attempt < maxRetries; attempt++) {
    code = generateShareCode(attempt);
    try {
      await env.DB.prepare(
        "INSERT INTO shared_automation_rules (code, rule_json, user_id) VALUES (?, ?, ?)"
      )
        .bind(code, ruleJson, userId)
        .run();
      break;
    } catch (e: unknown) {
      const error = e as Error;
      if (error.message?.includes("UNIQUE constraint failed") && attempt < maxRetries - 1) {
        continue;
      }
      throw e;
    }
  }

  return Response.json({ code });
});

/**
 * GET /api/automation/share/{code} —— 读共享规则。
 *
 * 注意此端点不需要鉴权（任何人都能读），因此直接解 URL，不再走 withAuth。
 */
export async function getShareRule(pathname: string, env: Env): Promise<Response> {
  const code = pathname.split("/").pop();

  if (!code || code.length !== 6) {
    return authErrorResponse(400, "Invalid share code");
  }

  const result = await env.DB.prepare(
    "SELECT rule_json FROM shared_automation_rules WHERE code = ?"
  )
    .bind(code.toUpperCase())
    .first<{ rule_json: string }>();

  if (!result) {
    return authErrorResponse(404, "Share code not found");
  }

  return Response.json({ ruleJson: result.rule_json });
}
