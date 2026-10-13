// test/index.spec.ts
import { env, createExecutionContext, waitOnExecutionContext, SELF } from 'cloudflare:test';
import { describe, it, expect } from 'vitest';
import jwt from '@tsndr/cloudflare-worker-jwt';
import worker from '../src/index';
import { generateShareCode } from '../src/share_code';
import schemaSQL from '../schema.sql?raw';

// For now, you'll need to do something like this to get a correctly-typed
// `Request` to pass to `worker.fetch()`.
const IncomingRequest = Request<unknown, IncomingRequestCfProperties>;

const API_BASE = 'https://example.com';

/**
 * 建表。schema.sql 是唯一事实来源，避免测试里再抄一份 DDL。
 *
 * 注意：`D1Database.exec()` 是**按行**执行的（注释行会被当成一条语句而报
 * `SQL code did not contain a statement`），所以这里先剥掉注释行，再按 `;`
 * 切成完整语句逐条 `prepare().run()`。
 */
async function migrate(): Promise<void> {
	const statements = schemaSQL
		.split(';')
		.map((chunk) =>
			chunk
				.split('\n')
				.filter((line) => !line.trim().startsWith('--'))
				.join('\n')
				.trim()
		)
		.filter((statement) => statement.length > 0);

	for (const statement of statements) {
		await env.DB.prepare(statement).run();
	}
}

/** 插入一个测试用户，返回自增主键（就是 JWT payload 里的 `id`）。 */
async function seedUser(appleUserId: string, credits: number): Promise<number> {
	const result = await env.DB.prepare('INSERT INTO users (apple_user_id, credits) VALUES (?, ?)')
		.bind(appleUserId, credits)
		.run();
	return result.meta.last_row_id as number;
}

/** 按服务端 `src/index.ts` 的口径签发一个合法 token。 */
async function signToken(id: number): Promise<string> {
	return jwt.sign({ id, exp: Math.floor(Date.now() / 1000) + 3600 }, env.JWT_SECRET);
}

describe('Worker', () => {
	it('responds with the API banner (unit style)', async () => {
		const request = new IncomingRequest(API_BASE);
		// Create an empty context to pass to `worker.fetch()`.
		const ctx = createExecutionContext();
		const response = await worker.fetch(request, env, ctx);
		// Wait for all `Promise`s passed to `ctx.waitUntil()` to settle before running test assertions
		await waitOnExecutionContext(ctx);
		expect(response.status).toBe(200);
		expect(await response.text()).toBe('YOYO Camera API');
	});

	it('responds with the API banner (integration style)', async () => {
		const response = await SELF.fetch(API_BASE);
		expect(response.status).toBe(200);
		expect(await response.text()).toBe('YOYO Camera API');
	});
});

/**
 * 回归测试：`verifyJWT` 必须是「非法 token → 401」而不是 500。
 *
 * 背景：`@tsndr/cloudflare-worker-jwt` 的 `jwt.verify` 返回类型是
 * `JwtData<{}, {}> | undefined`，**不是 boolean**；且遇到无法解析的字符串
 * （`"abc"`、空串、非 base64url 内容等）会直接抛 SyntaxError。
 * 早期实现把 `jwt.verify` 的返回值直接当布尔用，异常又被路由外层 catch 成 500，
 * 于是「token 写错」被误报成「服务端内部错误」。
 */
describe('GET /api/user authentication', () => {
	it('rejects a request with no Authorization header', async () => {
		const response = await SELF.fetch(`${API_BASE}/api/user`);
		expect(response.status).toBe(401);
		expect(await response.json()).toMatchObject({
			error: 'Missing or invalid authorization header',
		});
	});

	it('returns 401 (not 500) for malformed tokens', async () => {
		// 覆盖两类历史问题输入：固定假 token（debug.bypassAuth 用的）、非 JWT 字符串、结构像 JWT 但内容非法
		const malformed = ['debug-bypass-token', 'abc', 'a.b.c'];

		for (const token of malformed) {
			const response = await SELF.fetch(`${API_BASE}/api/user`, {
				headers: { Authorization: `Bearer ${token}` },
			});
			expect(response.status, `token=${JSON.stringify(token)}`).toBe(401);
			expect(await response.json()).toMatchObject({ error: 'Invalid token' });
		}
	});

	it('returns 401 for a blank Bearer token', async () => {
		// ⚠️ HTTP 头值的尾随空白会被运行时裁掉，`"Bearer "` 到服务端时已经是 `"Bearer"`，
		// 于是走的是「缺 Authorization」分支而不是「token 非法」分支 —— 两者都是 401。
		const response = await SELF.fetch(`${API_BASE}/api/user`, {
			headers: { Authorization: 'Bearer ' },
		});
		expect(response.status).toBe(401);
	});

	it('returns the profile for a valid token', async () => {
		await migrate();
		const id = await seedUser('test-user-001', 7);

		const response = await SELF.fetch(`${API_BASE}/api/user`, {
			headers: { Authorization: `Bearer ${await signToken(id)}` },
		});

		expect(response.status).toBe(200);
		expect(await response.json()).toMatchObject({
			id,
			appleUserId: 'test-user-001',
			credits: 7,
			subscriptionStatus: 0,
		});
	});

	it('returns 401 for a valid token signed with the wrong secret', async () => {
		await migrate();
		const id = await seedUser('test-user-002', 3);
		const forged = await jwt.sign({ id, exp: Math.floor(Date.now() / 1000) + 3600 }, 'not-the-secret');

		const response = await SELF.fetch(`${API_BASE}/api/user`, {
			headers: { Authorization: `Bearer ${forged}` },
		});
		expect(response.status).toBe(401);
	});

	it('returns 401 (not 500) for a valid token without a usable id', async () => {
		// 签名对得上、但 payload 里没有可用的 `id`。若不拦住，`undefined` 会被当作绑定参数
		// 传给 D1 并抛 D1_TYPE_ERROR，最终以 500 泄露内部错误 —— 应是 401。
		await migrate();
		const exp = Math.floor(Date.now() / 1000) + 3600;
		const unusable = [
			await jwt.sign({ exp }, env.JWT_SECRET), // 完全没有 id
			await jwt.sign({ id: 'not-a-number', exp }, env.JWT_SECRET), // id 类型不对
		];

		for (const token of unusable) {
			const response = await SELF.fetch(`${API_BASE}/api/user`, {
				headers: { Authorization: `Bearer ${token}` },
			});
			expect(response.status).toBe(401);
			expect(await response.json()).toMatchObject({ error: 'Invalid token payload' });
		}
	});
});

describe('generateShareCode', () => {
	it('generates 6 digits on first attempt', () => {
		const code = generateShareCode(0);
		expect(code).toMatch(/^\d{6}$/);
	});

	it('adds prefixed letters on conflicts (excluding O/I)', () => {
		const letter = '[A-HJ-NP-Z]';
		expect(generateShareCode(1)).toMatch(new RegExp(`^${letter}\\d{5}$`));
		expect(generateShareCode(2)).toMatch(new RegExp(`^${letter}{2}\\d{4}$`));
		expect(generateShareCode(6)).toMatch(new RegExp(`^${letter}{6}$`));

		const samples = [generateShareCode(1), generateShareCode(2), generateShareCode(6)].join('');
		expect(samples).not.toContain('O');
		expect(samples).not.toContain('I');
	});
});
