#!/bin/sh
# Post-deploy smoke test against the public CloudFront URL.
# Usage: scripts/smoke-test.sh https://dxxxx.cloudfront.net [expected_version]
set -eu
url="${1:?usage: smoke-test.sh <base-url> [expected-version]}"
expected_version="${2:-}"
fail() { echo "SMOKE FAIL: $*" >&2; exit 1; }

retry() { # CloudFront/ALB can take a moment after a deploy
  i=0
  until out=$(curl -fsS --max-time 10 "$@"); do
    i=$((i + 1)); [ "$i" -ge 10 ] && return 1; sleep 6
  done
  printf '%s' "$out"
}

echo "1/5 frontend served over HTTPS"
retry "$url/" | grep -q "<title>Guestbook</title>" || fail "index.html not served"

echo "2/5 HTTP redirects to HTTPS"
code=$(curl -s -o /dev/null -w '%{http_code}' "http://${url#https://}/")
[ "$code" = "301" ] || fail "expected 301 from http://, got $code"

echo "3/5 API liveness"
health=$(retry "$url/api/health") || fail "/api/health unreachable"
echo "    $health"
if [ -n "$expected_version" ]; then
  echo "$health" | grep -q "\"version\":\"$expected_version\"" || fail "running version is not $expected_version"
fi

echo "4/5 API readiness (database)"
retry "$url/api/ready" | grep -q '"database":"up"' || fail "database not reachable from API"

echo "5/5 write + read round trip"
marker="smoke-$(date +%s)"
curl -fsS --max-time 10 -X POST "$url/api/messages" \
  -H 'Content-Type: application/json' \
  -d "{\"author\":\"ci-smoke-test\",\"body\":\"$marker\"}" >/dev/null || fail "POST failed"
retry "$url/api/messages" | grep -q "$marker" || fail "written message not returned"

echo "SMOKE OK: $url"
