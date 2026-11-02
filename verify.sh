#!/usr/bin/env sh
# Confirm the nv-egress-deny NvSecurityRules were accepted and that Protect mode
# enforces them. Invalid rules are deleted by the NeuVector controller, so a
# missing object is a failed apply, not an empty cluster.
#
# Usage (from anywhere):
#   neuvector/egress-deny/verify.sh
# KUBECONFIG defaults to local.yaml at the repo root.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
export KUBECONFIG="${KUBECONFIG:-$ROOT/local.yaml}"
NS="${NS:-nv-egress-deny}"
SETTLE_SECONDS="${SETTLE_SECONDS:-8}"

fail=0

note() { printf '%s\n' "$*"; }
ok() { printf 'PASS: %s\n' "$*"; }
bad() { printf 'FAIL: %s\n' "$*"; fail=1; }

need_rule() {
  name="$1"
  if kubectl get nvsecurityrule "$name" -n "$NS" >/dev/null 2>&1; then
    mode="$(kubectl get nvsecurityrule "$name" -n "$NS" -o jsonpath='{.spec.target.policymode}')"
    if [ "$mode" = "Protect" ]; then
      ok "$name present, policymode=Protect"
    else
      bad "$name present but policymode=$mode"
    fi
  else
    bad "$name missing (NeuVector deletes invalid NvSecurityRules)"
  fi
}

# expect=allow|deny
# A completed TLS handshake counts as allowed, including HTTP 301/404.
probe() {
  deploy="$1"
  url="$2"
  expect="$3"
  pod="$(kubectl get pods -n "$NS" -l "app.kubernetes.io/name=$deploy" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  if [ -z "$pod" ]; then
    bad "$deploy has no pod for $url"
    return
  fi
  set +e
  out="$(kubectl exec -n "$NS" "$pod" -- curl -k -sS -o /dev/null \
    -w '%{http_code} %{remote_ip}' \
    --connect-timeout 5 --max-time 12 "$url" 2>&1)"
  rc=$?
  set -e
  code="$(printf '%s' "$out" | awk '{print $1}')"
  case "$code" in
    ''|*[!0-9]*) code=000 ;;
  esac
  if [ "$expect" = "allow" ]; then
    if [ "$rc" -eq 0 ] && [ "$code" != "000" ]; then
      ok "$deploy $url allowed ($out)"
    else
      bad "$deploy $url should be allowed (rc=$rc $out)"
    fi
  else
    if [ "$rc" -ne 0 ] || [ "$code" = "000" ]; then
      ok "$deploy $url denied (rc=$rc $out)"
    else
      bad "$deploy $url should be denied (rc=$rc $out)"
    fi
  fi
}

note "==> NvSecurityRules"
need_rule nv.deny-domain.nv-egress-deny
need_rule nv.allow-deny-domain.nv-egress-deny
need_rule nv.deny-ip-range.nv-egress-deny

note "==> settle ${SETTLE_SECONDS}s so the enforcer has the new rules"
sleep "$SETTLE_SECONDS"

note "==> deny example.org, allow other external names"
probe deny-domain https://example.org deny
probe deny-domain https://example.com allow

note "==> allow example.com, deny example.net"
probe allow-deny-domain https://example.com allow
probe allow-deny-domain https://example.net deny
probe allow-deny-domain https://example.org deny

note "==> deny 1.1.1.0/24, allow another external address"
probe deny-ip-range https://1.1.1.1 deny
probe deny-ip-range https://9.9.9.9 allow
probe deny-ip-range https://example.com allow

if [ "$fail" -ne 0 ]; then
  note "FAIL"
  exit 1
fi
note "PASS"
exit 0
