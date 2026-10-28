#!/usr/bin/env bash
# Build a Java truststore that trusts the certificates of a TLS-intercepting proxy, for the Gradle build of
# the release bundle (docs/release.md, "Building behind a TLS-intercepting proxy").
#
#   tools/release/make_truststore.sh <part of the certificates' names>      e.g. Netskope
#
# It copies the JDK's own cacerts, adds the matching certificates of the macOS System keychain, and writes
# the result to build/tls/truststore.jks (override the folder with TLS_DIR). Everything in it is public:
# the certificates are the proxy's CA certificates and the password is the JDK's well-known default.
# It refuses to overwrite an existing truststore: delete it first.
set -euo pipefail

if [ $# -ne 1 ] || [ -z "$1" ]; then
  echo "usage: $0 <part of the proxy certificates' names>" >&2
  exit 2
fi
name_part=$1

root=$(cd "$(dirname "$0")/../.." && pwd)
tls_dir=${TLS_DIR:-$root/build/tls}
truststore=$tls_dir/truststore.jks
password=changeit # the JDK's public default for cacerts

# The JDK of the Makefile: $JAVA_HOME, else the Homebrew JDK 17 it names, else the system's JDK 17.
java_home=${JAVA_HOME:-}
if [ -z "$java_home" ]; then
  java_home=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
  [ -d "$java_home" ] || java_home=$(/usr/libexec/java_home -v 17)
fi
keytool=$java_home/bin/keytool
cacerts=$java_home/lib/security/cacerts
[ -x "$keytool" ] || { echo "no keytool at $keytool" >&2; exit 1; }
[ -f "$cacerts" ] || { echo "no cacerts at $cacerts" >&2; exit 1; }

if [ -e "$truststore" ]; then
  echo "$truststore exists: delete it first if you want it rebuilt" >&2
  exit 1
fi

mkdir -p "$tls_dir"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

security find-certificate -a -c "$name_part" -p /Library/Keychains/System.keychain > "$work/all.pem"
awk -v dir="$work" '/BEGIN CERTIFICATE/ {n++} n {print > (dir "/cert" n ".pem")}' "$work/all.pem"
count=$(find "$work" -name 'cert*.pem' | wc -l | tr -d ' ')
if [ "$count" -eq 0 ]; then
  echo "no certificate with \"$name_part\" in its name in /Library/Keychains/System.keychain" >&2
  exit 1
fi

cp "$cacerts" "$work/truststore.jks"
chmod u+w "$work/truststore.jks"
for pem in "$work"/cert*.pem; do
  out=$("$keytool" -importcert -noprompt -trustcacerts -keystore "$work/truststore.jks" -storepass "$password" \
    -alias "proxy-$(basename "$pem" .pem)" -file "$pem" 2>&1) || { echo "$out" >&2; exit 1; }
done
mv "$work/truststore.jks" "$truststore"

echo "Wrote $truststore: the JDK's cacerts plus $count certificate(s) matching \"$name_part\"."
echo "Build in a terminal where you have run:"
echo "  export JAVA_TOOL_OPTIONS=\"-Djavax.net.ssl.trustStore=$truststore -Djavax.net.ssl.trustStorePassword=$password\""
