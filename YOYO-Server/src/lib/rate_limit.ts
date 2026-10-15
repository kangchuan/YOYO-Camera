/**
 * 简单的速率限制器（A-21 最低可行版本）。
 *
 * 设计目标：在不引入第三方依赖的前提下，把 AI 三个端点（/api/inspiration、
 * /api/inspiration/image、/api/ai_darkroom/process）按用户 id 做「每分钟 N 次」的限制。
 *
 * 实现：单条原子 SQL：
 *
 *   INSERT INTO rate_limits (user_id, bucket, window_start, count)
 *   VALUES (?, ?, ?, 1)
 *   ON CONFLICT(user_id, bucket) DO UPDATE SET
 *     count = CASE WHEN window_start + ? <= excluded.window_start THEN 1 ELSE count + 1 END,
 *     window_start = CASE WHEN window_start + ? <= excluded.window_start THEN excluded.window_start ELSE window_start END
 *
 * 用 SQLite 的 UPSERT 把 SELECT + INSERT/UPDATE 两条合成一条，从根本上避免
 * 「两个并发都看到 row=null → 两个都尝试 INSERT」造成的 UNIQUE constraint 失败。
 *
 * 已知不覆盖 / 取舍（已诚实列出）：
 * - 没用 KV / Durable Object，单 D1 写一条的开销 ≈ 5-15ms，对低 QPS 足够，
 *   但不适合高并发场景。
 * - 没有 IP 维度兜底：单一匿名 IP 也可以被多个 Apple id 注册；不过鉴权是
 *   先决条件，没有 token 就直接 401，所以这里影响很小。
 * - WINDOW_MS / LIMIT_PER_WINDOW 是常量，需要改可以发新版本；不做 env 配置。
 */

const WINDOW_MS = 60 * 1000; // 1 分钟窗口
const LIMIT_PER_WINDOW = 5; // 每个用户每分钟 5 次 AI 调用

export interface RateLimitResult {
  allowed: boolean;
  remaining: number;
  resetMs: number;
}

/** 一条原子 UPSERT：插入了就返回 count=1；冲突就 count+=1 并按需滚动窗口。 */
const UPSERT_SQL = `
INSERT INTO rate_limits (user_id, bucket, window_start, count)
VALUES (?1, ?2, ?3, 1)
ON CONFLICT(user_id, bucket) DO UPDATE SET
  count = CASE WHEN rate_limits.window_start + ?4 <= ?3 THEN 1 ELSE rate_limits.count + 1 END,
  window_start = CASE WHEN rate_limits.window_start + ?4 <= ?3 THEN ?3 ELSE rate_limits.window_start END
RETURNING window_start, count
`;

/**
 * 对一个 (user_id, bucket) 进行一次「消费」。
 *
 * 必须在调用之前用户已经通过了鉴权 —— 没有用户就限不了（其实整个请求会被 401）。
 * 返回对象给路由层判断 429 / 200。
 */
export async function consumeRateLimit(
  db: D1Database,
  userId: number,
  bucket: string
): Promise<RateLimitResult> {
  const now = Date.now();
  const row = await db
    .prepare(UPSERT_SQL)
    .bind(userId, bucket, now, WINDOW_MS)
    .first<{ window_start: number; count: number }>();

  if (!row) {
    // 理论上不会发生：UPSERT 总返回一行。失败兜底按「放行一次」。
    return { allowed: true, remaining: LIMIT_PER_WINDOW - 1, resetMs: WINDOW_MS };
  }

  const elapsed = now - row.window_start;
  if (elapsed >= WINDOW_MS) {
    // 边界：UPSERT 把 count 重置成 1（excluded.window_start > old+window_ms），
    // 但 elapsed 的「现在 - window_start」还可能因为时钟偏移或处理延迟留在边界上。
    // 这里把 resetMs 当下限保证为正。
    return { allowed: true, remaining: LIMIT_PER_WINDOW - 1, resetMs: WINDOW_MS };
  }

  const allowed = row.count <= LIMIT_PER_WINDOW;
  return {
    allowed,
    remaining: Math.max(0, LIMIT_PER_WINDOW - row.count),
    resetMs: WINDOW_MS - elapsed,
  };
}
