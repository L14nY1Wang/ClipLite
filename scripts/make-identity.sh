#!/bin/bash
# 幂等地创建稳定的本地代码签名身份 "SnapLite Dev"：清理旧证书 → 生成 → 导入 → 设为受信 → 校验。
# ⚠️ 在【你自己的“终端”App】里运行；导入/信任可能弹窗，输入你的 Mac 登录密码并点允许。
#     bash "/Users/lianyi/Workspace/截屏软件/scripts/make-identity.sh"
set -e
IDENT="SnapLite Dev"
KC="$HOME/Library/Keychains/login.keychain-db"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

echo "1) 清理旧的 $IDENT 证书…"
while :; do
  h=$(security find-certificate -a -c "$IDENT" -Z "$KC" 2>/dev/null | awk '/SHA-1/{print $3; exit}')
  [ -z "$h" ] && break
  security delete-certificate -Z "$h" "$KC" >/dev/null 2>&1 || break
done

echo "2) 生成自签名证书…"
openssl req -x509 -newkey rsa:2048 -keyout "$TMP/k.pem" -out "$TMP/c.pem" -days 3650 -nodes \
  -subj "/CN=$IDENT/O=ClipLite/OU=LocalDev" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" >/dev/null 2>&1
openssl pkcs12 -export -legacy -inkey "$TMP/k.pem" -in "$TMP/c.pem" \
  -out "$TMP/id.p12" -passout pass:cliplite >/dev/null 2>&1 \
|| openssl pkcs12 -export -inkey "$TMP/k.pem" -in "$TMP/c.pem" \
   -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 \
   -out "$TMP/id.p12" -passout pass:cliplite >/dev/null 2>&1

echo "3) 导入登录钥匙串（弹框请输入 Mac 登录密码 / 点允许）…"
security import "$TMP/id.p12" -k "$KC" -P cliplite -T /usr/bin/codesign >/dev/null

echo "4) 设为“代码签名”受信（可能再次要密码/确认）…"
security find-certificate -c "$IDENT" -p "$KC" > "$TMP/cert.pem"
security add-trusted-cert -r trustRoot -p codeSign -k "$KC" "$TMP/cert.pem"

echo
echo "✅ 校验有效身份："
if security find-identity -v -p codesigning "$KC" 2>/dev/null | grep -q "$IDENT"; then
  security find-identity -v -p codesigning "$KC" | grep "$IDENT"
  echo
  echo "接着运行： cd \"/Users/lianyi/Workspace/截屏软件\" && make reset-perm && make app && open build/ClipLite.app"
  echo "首次 codesign 若弹“想要使用密钥 $IDENT”，点【始终允许】。"
else
  echo "❌ 仍无有效身份。请把本脚本完整输出发给我。"
fi
