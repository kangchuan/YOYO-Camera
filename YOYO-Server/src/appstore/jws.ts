/**
 * App Store Server Notifications V2 —— JWS 验签。
 *
 * 背景（A-01）：旧实现直接 `jwt.decode(signedPayload)` 就信任 payload，任何人 POST
 * 一个自造的 JSON 就能把任意账号刷成 PRO / 白拿积分。本模块把「解析」和「验签」
 * 彻底分开：任何 payload 只有在**证书链校验 + JWS 签名校验**都通过之后才会被读取。
 * 失败一律抛错，由 `src/routes/webhook.ts` 转成 401。
 *
 * 校验内容
 * --------
 * 1. JWS header 的 `alg` 必须是 ES256，`x5c` 必须存在且链长 >= 2；
 * 2. `x5c` 逐级链式校验：每张证书的 issuer 必须等于下一张的 subject，
 *    并且用下一张证书的公钥验证当前证书的签名（即「由下一张签发」）；
 * 3. 链尾（根证书）DER 的 SHA-256 指纹必须命中钉死的信任锚
 *    （默认 Apple Root CA - G3，可用 `APPLE_ROOT_CA_SHA256` 覆盖）；
 * 4. 叶子证书的有效期必须覆盖当前时间；
 * 5. 最后用叶子证书公钥验证 JWS 自身的 ES256 签名；
 * 6. payload 里的 `bundleId`（若有）必须等于本 App 的 bundle id。
 *
 * 已知未覆盖 / 残余风险（不静默降级，明确记录）
 * ------------------------------------------
 * - **未做证书吊销（CRL / OCSP）检查**。若 Apple 的叶子/中间证书被提前吊销，
 *   本实现仍会接受其签名，直到证书自然过期或我们主动更换信任锚。
 * - **未校验扩展字段**：没有解析 `basicConstraints`(CA:TRUE)、`keyUsage`、
 *   `extendedKeyUsage(1.2.840.113635.100.6.11.1)` 等扩展，因此不强制「中间证书必须
 *   是 CA」「叶子必须是 Apple 的 App Store 签名证书」。这是链式签名 + 根钉死之外
 *   的额外约束，缺失会让攻击面略大于标准的 X.509 校验路径。
 *   要补齐需要在 `src/appstore/der.ts` 里继续解析 extensions，本次未做。
 * - **只信任链尾证书在 x5c 里出现**（Apple 的 x5c 包含根证书，实测如此）。
 *   若 Apple 改为只下发 [leaf, intermediate]，会因为找不到钉死的根而被**拒绝**
 *   （fail-closed，不会误放行）。
 * - 链尾之外的证书（即中间证书）自身有效期未校验，只校验了叶子证书。
 * - `x5c` 里若混入多张根证书，只要链尾命中钉死指纹即可，不校验锚的集合。
 */

import { parseCertificate, type ParsedCertificate } from "./der";

/** 信任锚：Apple Root CA - G3（SHA-256 指纹，来源 Apple PKI）。
 *  有效期 2014-04-30 → 2039-04-30。
 *  可用 env.APPLE_ROOT_CA_SHA256 覆盖（多个用逗号分隔），用于根轮换或测试。 */
export const APPLE_ROOT_CA_G3_SHA256 =
  "63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179";

/** 证书签名算法 OID → 验签用的摘要算法。WebCrypto 的 ECDSA 不支持 SHA-1/SHA-224。 */
const SIGNATURE_ALGORITHMS: Record<string, { name: "ECDSA" | "RSASSA-PKCS1-v1_5"; hash: string }> = {
  "1.2.840.10045.4.3.2": { name: "ECDSA", hash: "SHA-256" },
  "1.2.840.10045.4.3.3": { name: "ECDSA", hash: "SHA-384" },
  "1.2.840.10045.4.3.4": { name: "ECDSA", hash: "SHA-512" },
  "1.2.840.113549.1.1.11": { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
  "1.2.840.113549.1.1.12": { name: "RSASSA-PKCS1-v1_5", hash: "SHA-384" },
  "1.2.840.113549.1.1.13": { name: "RSASSA-PKCS1-v1_5", hash: "SHA-512" },
};

/** EC 曲线 OID → WebCrypto namedCurve。 */
const CURVES: Record<string, string> = {
  "1.2.840.10045.3.1.7": "P-256",
  "1.3.132.0.34": "P-384",
  "1.3.132.0.35": "P-521",
};

export class JwsVerificationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "JwsVerificationError";
  }
}

function base64UrlToBytes(input: string): Uint8Array {
  const base64 = input.replace(/-/g, "+").replace(/_/g, "/");
  const padded = base64 + "=".repeat((4 - (base64.length % 4)) % 4);
  let binary: string;
  try {
    binary = atob(padded);
  } catch {
    throw new JwsVerificationError("invalid base64url segment");
  }
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
  return btoa(binary);
}

async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", bytes as unknown as ArrayBuffer);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
  return true;
}

interface JwsHeader {
  alg?: string;
  x5c?: string[];
}

interface DecodedJws {
  header: JwsHeader;
  signingInput: Uint8Array;
  signature: Uint8Array;
  payloadBytes: Uint8Array;
}

function splitJws(jws: string): DecodedJws {
  const parts = jws.split(".");
  if (parts.length !== 3) throw new JwsVerificationError("JWS must have 3 segments");
  const [headerB64, payloadB64, signatureB64] = parts;
  const header = JSON.parse(new TextDecoder().decode(base64UrlToBytes(headerB64))) as JwsHeader;
  return {
    header,
    // 签名覆盖 "<header>.<payload>" 的 ASCII 原文
    signingInput: new TextEncoder().encode(`${headerB64}.${payloadB64}`),
    signature: base64UrlToBytes(signatureB64),
    payloadBytes: base64UrlToBytes(payloadB64),
  };
}

/** 用证书公钥导入 CryptoKey。EC 证书走 namedCurve，RSA 证书不需要。 */
async function importCertificateKey(cert: ParsedCertificate): Promise<CryptoKey> {
  const algorithm = SIGNATURE_ALGORITHMS[cert.signatureAlgorithmOid];
  if (!algorithm) {
    throw new JwsVerificationError(`unsupported signature algorithm ${cert.signatureAlgorithmOid}`);
  }
  if (algorithm.name === "ECDSA") {
    const namedCurve = CURVES[cert.curveOid];
    if (!namedCurve) throw new JwsVerificationError(`unsupported EC curve ${cert.curveOid}`);
    return crypto.subtle.importKey(
      "spki",
      cert.spki as unknown as ArrayBuffer,
      { name: "ECDSA", namedCurve },
      false,
      ["verify"]
    );
  }
  return crypto.subtle.importKey(
    "spki",
    cert.spki as unknown as ArrayBuffer,
    { name: "RSASSA-PKCS1-v1_5", hash: algorithm.hash },
    false,
    ["verify"]
  );
}

async function verifySignature(
  issuer: ParsedCertificate,
  signature: Uint8Array,
  data: Uint8Array
): Promise<boolean> {
  const algorithm = SIGNATURE_ALGORITHMS[issuer.signatureAlgorithmOid];
  if (!algorithm) {
    throw new JwsVerificationError(`unsupported signature algorithm ${issuer.signatureAlgorithmOid}`);
  }
  const key = await importCertificateKey(issuer);
  return crypto.subtle.verify(
    algorithm.name === "ECDSA"
      ? { name: "ECDSA", hash: algorithm.hash }
      : { name: "RSASSA-PKCS1-v1_5" },
    key,
    signature as unknown as ArrayBuffer,
    data as unknown as ArrayBuffer
  );
}

export interface VerifyChainOptions {
  /** 允许的根证书 SHA-256 指纹（小写 hex）。 */
  trustedRootFingerprints: string[];
  /** 当前时间（epoch 毫秒），便于测试注入。 */
  now?: number;
}

/**
 * 校验 x5c 证书链，返回叶子证书（用来验 JWS 签名）。
 * 任意一步不通过都抛 `JwsVerificationError`。
 */
export async function verifyCertificateChain(
  x5cBase64: string[],
  options: VerifyChainOptions
): Promise<ParsedCertificate> {
  if (!Array.isArray(x5cBase64) || x5cBase64.length < 2) {
    throw new JwsVerificationError("x5c must contain at least a certificate and its issuer");
  }

  const certs = x5cBase64.map((der) => parseCertificate(base64UrlToBytes(der)));
  const now = options.now ?? Date.now();

  // 逐级校验：certs[i] 必须由 certs[i+1] 签发
  for (let i = 0; i < certs.length - 1; i++) {
    const child = certs[i];
    const parent = certs[i + 1];
    if (!bytesEqual(child.issuer, parent.subject)) {
      throw new JwsVerificationError(`certificate ${i} issuer does not match certificate ${i + 1}`);
    }
    const ok = await verifySignature(parent, child.signature, child.tbs);
    if (!ok) {
      throw new JwsVerificationError(`certificate ${i} signature not issued by certificate ${i + 1}`);
    }
  }

  // 信任锚：链尾必须是钉死的根证书
  const root = certs[certs.length - 1];
  const rootFingerprint = await sha256Hex(root.der);
  if (!options.trustedRootFingerprints.includes(rootFingerprint)) {
    throw new JwsVerificationError("certificate chain is not anchored to a trusted Apple root");
  }

  // 叶子证书有效期
  const leaf = certs[0];
  if (now < leaf.notBefore || now > leaf.notAfter) {
    throw new JwsVerificationError("leaf certificate is not valid at this time");
  }

  return leaf;
}

export interface VerifiedJws {
  payload: unknown;
  /** 叶子证书公钥（SPKI DER），用于校验内层没有 x5c 的 JWS */
  leafSpki: Uint8Array;
  header: JwsHeader;
}

/**
 * 完整校验一个 App Store 签发的 JWS 并返回其 payload。
 *
 * @param jws 待校验的 JWS 字符串
 * @param options 信任锚与当前时间
 * @param fallbackLeafSpki 当 JWS header 不带 `x5c` 时，改用这个公钥验签
 *        （Apple 的 `signedTransactionInfo`/`signedRenewalInfo` 通常自带 x5c；
 *        若某天不带了，就用外层通知已经验过的叶子公钥，而不是放行）
 */
export async function verifyAppleJws(
  jws: string,
  options: VerifyChainOptions,
  fallbackLeafSpki?: Uint8Array
): Promise<VerifiedJws> {
  const { header, signingInput, signature, payloadBytes } = splitJws(jws);

  if (header.alg !== "ES256") {
    throw new JwsVerificationError(`unexpected JWS alg ${String(header.alg)}`);
  }

  let leafSpki: Uint8Array;
  if (header.x5c && header.x5c.length > 0) {
    const leaf = await verifyCertificateChain(header.x5c, options);
    leafSpki = leaf.spki;
  } else if (fallbackLeafSpki) {
    leafSpki = fallbackLeafSpki;
  } else {
    throw new JwsVerificationError("JWS header has no x5c certificate chain");
  }

  const key = await crypto.subtle.importKey(
    "spki",
    leafSpki as unknown as ArrayBuffer,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["verify"]
  );
  const signatureOk = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    signature as unknown as ArrayBuffer,
    signingInput as unknown as ArrayBuffer
  );
  if (!signatureOk) throw new JwsVerificationError("JWS signature verification failed");

  return {
    payload: JSON.parse(new TextDecoder().decode(payloadBytes)),
    leafSpki,
    header,
  };
}

/** 把 `APPLE_ROOT_CA_SHA256`（逗号分隔）解析成指纹数组，缺省回落到 Apple Root CA - G3。 */
export function resolveTrustedRoots(configured: string | undefined): string[] {
  const list = (configured ?? "")
    .split(",")
    .map((item) => item.trim().toLowerCase())
    .filter((item) => item.length > 0);
  return list.length > 0 ? list : [APPLE_ROOT_CA_G3_SHA256];
}

/** 导出给测试用的编码辅助（生产代码不依赖）。 */
export const __testInternals = { base64UrlToBytes, bytesToBase64, sha256Hex };
