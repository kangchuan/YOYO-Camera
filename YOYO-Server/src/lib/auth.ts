/**
 * 路由共用的鉴权 + 响应助手（A-07）。
 *
 * 修复前：8 个需要 Bearer JWT 的端点各自复制「拿 header → split(' ')[1] → verifyJWT
 *  → getUserId → 401 / 401 / 401」五个分支，任何一处写错就潜规则飘移。
 *
 * 修复后：
 *   - `withAuth(handler)` 高阶函数包住路由实现，把鉴权和 401 收口到这里。
 *   - `requireUser(request, env)` 解出来的 `userId` 已通过签名 / 过期 / payload 形状
 *     三层校验，调用方拿到的就是正整数 id。
 *   - 错误响应统一用 `authErrorResponse(status, message)`，CORS headers 也一并带上，
 *     避免某个端点忘了塞 `Access-Control-Allow-*` 导致浏览器侧炸掉。
 *
 * 注意：`withAuth` 会**完全替换**原来的请求 —— 它会在 `handler(userId, request, env)`
 * 上继续跑，调用方拿到的就是鉴权通过的请求。校验失败的直接返回 Response，handler
 * 不会被调用。
 */

import jwt from "@tsndr/cloudflare-worker-jwt";

const JWT_INVALID_PAYLOAD = "Invalid token payload";

/** CORS header（与 src/index.ts 一致；这里再导出一份避免循环依赖）。 */
function corsHeaders(): Record<string, string> {
  // 实际允许的 origin 在 src/index.ts 的 `fetch` 入口里决定（基于 env.CORS_ALLOW_ORIGIN）。
  // 这里保留 "*" 兜底，默认值用配置覆盖。
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, DELETE, PUT, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
  };
}

export function authErrorResponse(
  status: number,
  message: string,
  extraHeaders?: Record<string, string>
): Response {
  return Response.json({ error: message }, { status, headers: { ...corsHeaders(), ...extraHeaders } });
}

/**
 * 校验 JWT，把「token 格式非法」统一收敛为 false。
 *
 * `jwt.verify` 遇到无法解析的字符串会抛 `SyntaxError`，把异常转成 false 后，调用方
 * 拿到的就是「非法」而不是 500 —— 这一直是 YOYO 的回归测试覆盖点。
 */
export async function verifyJWT(token: string, secret: string): Promise<boolean> {
  try {
    return Boolean(await jwt.verify(token, secret));
  } catch {
    return false;
  }
}

/**
 * 从**已验签**的 token 中取出用户 id。
 *
 * 必须已经过 `verifyJWT`。`jwt.decode` 不校验，对畸形字符串会抛错；这里用 try 包住，
 * 任何异常按 `null` 处理，与 401 等价。
 */
export function getUserId(token: string): number | null {
  try {
    const { payload } = jwt.decode(token);
    const id = (payload as { id?: unknown }).id;
    return typeof id === "number" && Number.isSafeInteger(id) && id > 0 ? id : null;
  } catch {
    return null;
  }
}

/** 标准 401 响应。 */
function unauthorized(message: string): Response {
  return authErrorResponse(401, message);
}

/**
 * 把「需要 Bearer token」的路由用 `withAuth` 包起来。
 *
 * 调用方只关心 `userId` 拿到之后的业务逻辑；签名 / payload / 头部等等全部外包。
 *
 * @example
 *   router.post("/api/user", withAuth(async (userId, req, env) => {
 *     // ...
 *   }));
 */
export function withAuth<T = unknown>(
  handler: (userId: number, request: Request, env: Env) => Promise<T>
): (request: Request, env: Env) => Promise<T | Response> {
  return async (request: Request, env: Env) => {
    const authHeader = request.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return unauthorized("Missing or invalid authorization header");
    }

    const token = authHeader.slice("Bearer ".length).trim();
    if (!token) {
      return unauthorized("Missing or invalid authorization header");
    }

    const valid = await verifyJWT(token, env.JWT_SECRET);
    if (!valid) {
      return unauthorized("Invalid token");
    }

    const userId = getUserId(token);
    if (userId === null) {
      return unauthorized(JWT_INVALID_PAYLOAD);
    }

    return handler(userId, request, env);
  };
}
