/**
 * Apple Sign In identity token 校验（A-06）。
 *
 * 之前只校验了 `iss` / `exp` / `sub` 和 JWS 签名，**没有**校验 `aud`：
 * 任何合法的 Apple identityToken 都能登进来。攻击者抓一个 iOS 端的 token，
 * 把它塞到 `/api/auth/apple` 就能用别人 Apple id 登进来 —— 而且 `sub` 一致，
 * 看起来就像受害者。
 *
 * 修复：调用方必须传入 `expectedAudience`，与 Apple 颁发的 `aud` 字段比较，
 * 不一致直接返回 false。`aud` 在 iOS 端是 App 的 bundle id，所以传
 * `env.APP_STORE_BUNDLE_ID`（与 iOS App 实际一致）。
 *
 * 保留项：JWKS 缓存、签名校验、`iss=https://appleid.apple.com`、`exp`、`sub`。
 * 改动只在最末加 `aud` 比对；既有行为不回退。
 */

interface AppleJWK {
  kty: string;
  kid: string;
  use: string;
  alg: string;
  n: string;
  e: string;
}

interface AppleJWKS {
  keys: AppleJWK[];
}

interface JWTHeader {
  alg: string;
  kid: string;
}

interface AppleJWTPayload {
  iss: string;
  aud: string;
  exp: number;
  iat: number;
  sub: string;
  email?: string;
  email_verified?: string;
  is_private_email?: string;
  auth_time: number;
  nonce_supported: boolean;
}

// Cache Apple's public keys (in-memory as secondary cache)
let cachedKeys: AppleJWKS | null = null;
let cacheExpiry = 0;

const APPLE_KEYS_URL = "https://appleid.apple.com/auth/keys";
const CACHE_TTL = 24 * 60 * 60; // 24 hours in seconds

async function getApplePublicKeys(): Promise<AppleJWKS> {
  // 1. Check in-memory cache first (fastest within same isolate)
  const now = Date.now();
  if (cachedKeys && now < cacheExpiry) {
    return cachedKeys;
  }

  // 2. Check Cloudflare Cache API (shared across isolates)
  const cache = caches.default;
  const cacheKey = new Request(APPLE_KEYS_URL);

  let response = await cache.match(cacheKey);

  if (!response) {
    // 3. Cache miss, fetch from Apple
    const freshResponse = await fetch(APPLE_KEYS_URL);
    if (!freshResponse.ok) {
      throw new Error("Failed to fetch Apple public keys");
    }

    // Clone response and add cache control headers
    const responseToCache = new Response(freshResponse.body, {
      headers: {
        "Content-Type": "application/json",
        "Cache-Control": `public, max-age=${CACHE_TTL}`,
      },
    });

    // Store in edge cache (non-blocking)
    await cache.put(cacheKey, responseToCache.clone());
    response = responseToCache;
  }

  // 4. Update in-memory cache
  cachedKeys = await response.json();
  cacheExpiry = now + CACHE_TTL * 1000;

  return cachedKeys!;
}

function base64UrlDecode(str: string): Uint8Array {
  // Replace URL-safe characters
  const base64 = str.replace(/-/g, "+").replace(/_/g, "/");
  // Add padding if needed
  const padded = base64 + "=".repeat((4 - (base64.length % 4)) % 4);
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

function decodeJWT(token: string): { header: JWTHeader; payload: AppleJWTPayload } {
  const parts = token.split(".");
  if (parts.length !== 3) {
    throw new Error("Invalid JWT format");
  }

  const header = JSON.parse(new TextDecoder().decode(base64UrlDecode(parts[0])));
  const payload = JSON.parse(new TextDecoder().decode(base64UrlDecode(parts[1])));

  return { header, payload };
}

async function importPublicKey(jwk: AppleJWK): Promise<CryptoKey> {
  return await crypto.subtle.importKey(
    "jwk",
    {
      kty: jwk.kty,
      n: jwk.n,
      e: jwk.e,
      alg: jwk.alg,
      use: jwk.use,
    },
    {
      name: "RSASSA-PKCS1-v1_5",
      hash: { name: "SHA-256" },
    },
    false,
    ["verify"]
  );
}

/**
 * 校验 Apple identityToken。
 *
 * @param identityToken Apple 颁发的 identityToken
 * @param expectedSubject 期望的 `sub`（即 Apple user identifier）
 * @param expectedAudience 期望的 `aud`（即本 App 的 bundle id）—— **A-06 必须传**
 * @returns 全部校验通过返回 true；任意一步失败返回 false
 */
export async function verifyAppleIdentityToken(
  identityToken: string,
  expectedSubject: string,
  expectedAudience: string
): Promise<boolean> {
  try {
    const { header, payload } = decodeJWT(identityToken);

    // Get Apple's public keys
    const jwks = await getApplePublicKeys();
    const jwk = jwks.keys.find((key) => key.kid === header.kid);
    if (!jwk) {
      console.error("No matching key found for kid:", header.kid);
      return false;
    }

    // Verify signature
    const parts = identityToken.split(".");
    const signatureInput = new TextEncoder().encode(`${parts[0]}.${parts[1]}`);
    const signature = base64UrlDecode(parts[2]);

    const publicKey = await importPublicKey(jwk);
    const isValidSignature = await crypto.subtle.verify(
      "RSASSA-PKCS1-v1_5",
      publicKey,
      signature,
      signatureInput
    );

    if (!isValidSignature) {
      console.error("Invalid signature");
      return false;
    }

    // Verify claims
    const now = Math.floor(Date.now() / 1000);

    // Check issuer
    if (payload.iss !== "https://appleid.apple.com") {
      console.error("Invalid issuer:", payload.iss);
      return false;
    }

    // Check expiration
    if (payload.exp < now) {
      console.error("Token expired");
      return false;
    }

    // Check subject matches userIdentifier
    if (payload.sub !== expectedSubject) {
      console.error("Subject mismatch");
      return false;
    }

    // A-06: Check audience. Apple 把 iOS 端 App bundle id 放在 aud 字段；
    // 不一致说明这个 token 是另一个 app 颁的，绝不能登进来。
    if (typeof payload.aud !== "string" || payload.aud !== expectedAudience) {
      console.error("Audience mismatch", { expected: expectedAudience, got: payload.aud });
      return false;
    }

    return true;
  } catch (error) {
    console.error("Token verification error:", error);
    return false;
  }
}
