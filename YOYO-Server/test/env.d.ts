declare module 'cloudflare:test' {
	interface ProvidedEnv extends Env {}
}

// Vite 的 `?raw` 导入（测试里用它读 schema.sql，保证 DDL 只有一份）
declare module '*?raw' {
	const content: string;
	export default content;
}
