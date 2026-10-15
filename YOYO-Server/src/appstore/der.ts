/**
 * 极简 DER（ASN.1）解析器，只覆盖 X.509 证书验签所需的字段。
 *
 * 设计取舍：Cloudflare Workers 运行时**没有** X509 解析 API（无 `X509Certificate`、
 * 无 `crypto.X509`），也没有 OpenSSL 绑定，因此无法像 Node 那样 `new X509Certificate(der)`。
 * 要在 Workers 里做证书链校验，只能自己解析 DER 取出：
 *   - TBSCertificate 的原始字节（被签名的数据）
 *   - signatureValue（签名值）
 *   - signatureAlgorithm 的 OID（决定验签用的摘要算法）
 *   - SubjectPublicKeyInfo 的原始字节 + 曲线 OID（交给 `crypto.subtle.importKey("spki", ...)`）
 *   - issuer / subject 的原始字节（用 DER 字节相等判断「上一级由下一级签发」）
 *
 * 本文件**不**作为通用 ASN.1 库使用，只保证对 Apple 签发的证书（以及测试里构造的
 * 等价结构）正确。所有解析失败都抛异常，由调用方统一转成认证失败（401）。
 */

export interface Tlv {
  /** tag 字节（只支持单字节 tag，够用） */
  tag: number;
  /** 该 TLV 起始偏移 */
  start: number;
  /** value 起始偏移 */
  valueStart: number;
  /** value 结束偏移（exclusive） */
  valueEnd: number;
  /** 该 TLV 结束偏移（exclusive） */
  end: number;
}

const TAG_SEQUENCE = 0x30;
const TAG_SET = 0x31;
const TAG_INTEGER = 0x02;
const TAG_BIT_STRING = 0x03;
const TAG_OID = 0x06;
const TAG_UTC_TIME = 0x17;
const TAG_GENERALIZED_TIME = 0x18;
const TAG_CONTEXT_0 = 0xa0;

export function readTlv(buf: Uint8Array, offset: number): Tlv {
  if (offset + 2 > buf.length) throw new Error("DER: truncated TLV header");
  const tag = buf[offset];
  let p = offset + 1;
  const first = buf[p++];
  let length = 0;
  if (first & 0x80) {
    const count = first & 0x7f;
    // 0x80 是不定长编码，DER 禁止；>4 字节的长度超出 JS 安全范围
    if (count === 0 || count > 4) throw new Error("DER: unsupported length encoding");
    if (p + count > buf.length) throw new Error("DER: truncated length");
    for (let i = 0; i < count; i++) length = length * 256 + buf[p++];
  } else {
    length = first;
  }
  const valueStart = p;
  const valueEnd = valueStart + length;
  if (valueEnd > buf.length) throw new Error("DER: value out of range");
  return { tag, start: offset, valueStart, valueEnd, end: valueEnd };
}

export function readChildren(buf: Uint8Array, parent: Tlv): Tlv[] {
  const out: Tlv[] = [];
  let p = parent.valueStart;
  while (p < parent.valueEnd) {
    const child = readTlv(buf, p);
    out.push(child);
    p = child.end;
  }
  return out;
}

/** 取某个 TLV 的完整原始字节（含 tag/length）。 */
export function rawBytes(buf: Uint8Array, tlv: Tlv): Uint8Array {
  return buf.subarray(tlv.start, tlv.end);
}

export function expectTag(tlv: Tlv, tag: number, what: string): void {
  if (tlv.tag !== tag) {
    throw new Error(`DER: expected ${what} (tag 0x${tag.toString(16)})`);
  }
}

export function decodeOid(buf: Uint8Array, tlv: Tlv): string {
  expectTag(tlv, TAG_OID, "OID");
  const bytes = buf.subarray(tlv.valueStart, tlv.valueEnd);
  if (bytes.length === 0) throw new Error("DER: empty OID");
  const parts: number[] = [Math.floor(bytes[0] / 40), bytes[0] % 40];
  let value = 0;
  for (let i = 1; i < bytes.length; i++) {
    value = value * 128 + (bytes[i] & 0x7f);
    if (!(bytes[i] & 0x80)) {
      parts.push(value);
      value = 0;
    }
  }
  return parts.join(".");
}

function decodeAscii(buf: Uint8Array, tlv: Tlv): string {
  return new TextDecoder().decode(buf.subarray(tlv.valueStart, tlv.valueEnd));
}

/** UTCTime(0x17) / GeneralizedTime(0x18) → epoch 毫秒。 */
export function decodeTime(buf: Uint8Array, tlv: Tlv): number {
  const s = decodeAscii(buf, tlv);
  const nums = /^(\d{2}|\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$/.exec(s);
  if (!nums) throw new Error("DER: unsupported time format");
  const [, y, mo, d, h, mi, sec] = nums;
  let year: number;
  if (tlv.tag === TAG_UTC_TIME) {
    const yy = Number(y);
    year = yy >= 50 ? 1900 + yy : 2000 + yy;
  } else if (tlv.tag === TAG_GENERALIZED_TIME) {
    year = Number(y);
  } else {
    throw new Error("DER: unsupported time tag");
  }
  return Date.UTC(year, Number(mo) - 1, Number(d), Number(h), Number(mi), Number(sec));
}

// ---------------------------------------------------------------------------
// X.509 Certificate
// ---------------------------------------------------------------------------

export interface ParsedCertificate {
  /** 证书完整 DER 字节（用于算根证书指纹） */
  der: Uint8Array;
  /** TBSCertificate 的原始字节（被签名的内容） */
  tbs: Uint8Array;
  /** SubjectPublicKeyInfo 的原始字节（可交给 crypto.subtle.importKey("spki")） */
  spki: Uint8Array;
  /** 证书签名算法 OID，例如 1.2.840.10045.4.3.2（ecdsa-with-SHA256） */
  signatureAlgorithmOid: string;
  /** 证书签名的原始字节（DER 编码的 ECDSA r||s 或 RSA 签名） */
  signature: Uint8Array;
  /** 公钥所属曲线 OID（EC 证书才有） */
  curveOid: string;
  /** issuer Name 的 DER 字节 */
  issuer: Uint8Array;
  /** subject Name 的 DER 字节 */
  subject: Uint8Array;
  /** 有效期起（epoch 毫秒） */
  notBefore: number;
  /** 有效期止（epoch 毫秒） */
  notAfter: number;
}

/**
 * Certificate ::= SEQUENCE { tbsCertificate, signatureAlgorithm, signatureValue }
 * TBSCertificate ::= SEQUENCE {
 *   [0] version DEFAULT v1, serialNumber, signature, issuer,
 *   validity, subject, subjectPublicKeyInfo, ... }
 */
export function parseCertificate(der: Uint8Array): ParsedCertificate {
  const cert = readTlv(der, 0);
  expectTag(cert, TAG_SEQUENCE, "Certificate");
  if (cert.end !== der.length) throw new Error("DER: trailing bytes after Certificate");

  const certKids = readChildren(der, cert);
  if (certKids.length < 3) throw new Error("DER: malformed Certificate");
  const [tbsTlv, sigAlgTlv, sigValueTlv] = certKids;
  expectTag(tbsTlv, TAG_SEQUENCE, "TBSCertificate");
  expectTag(sigValueTlv, TAG_BIT_STRING, "signatureValue");

  // BIT STRING 第一个字节是「未使用比特数」，DER 下必为 0
  if (der[sigValueTlv.valueStart] !== 0) throw new Error("DER: non-octet-aligned signature");
  const signature = der.subarray(sigValueTlv.valueStart + 1, sigValueTlv.valueEnd);

  const tbsKids = readChildren(der, tbsTlv);
  let i = 0;
  if (tbsKids[i].tag === TAG_CONTEXT_0) i++; // v3 的 [0] EXPLICIT version
  expectTag(tbsKids[i], TAG_INTEGER, "serialNumber");
  i++;
  const sigAlgInner = tbsKids[i++];
  const issuer = tbsKids[i++];
  const validity = tbsKids[i++];
  const subject = tbsKids[i++];
  const spki = tbsKids[i++];
  if (!spki) throw new Error("DER: missing subjectPublicKeyInfo");

  const validityKids = readChildren(der, validity);
  if (validityKids.length < 2) throw new Error("DER: malformed Validity");

  const sigAlgKids = readChildren(der, sigAlgInner);
  const signatureAlgorithmOid = decodeOid(der, sigAlgKids[0]);

  const spkiKids = readChildren(der, spki);
  const spkiAlgKids = readChildren(der, spkiKids[0]);
  const curveOid = spkiAlgKids[1] ? decodeOid(der, spkiAlgKids[1]) : "";

  return {
    der,
    tbs: rawBytes(der, tbsTlv),
    spki: rawBytes(der, spki),
    signatureAlgorithmOid,
    signature,
    curveOid,
    issuer: rawBytes(der, issuer),
    subject: rawBytes(der, subject),
    notBefore: decodeTime(der, validityKids[0]),
    notAfter: decodeTime(der, validityKids[1]),
  };
}
