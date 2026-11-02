# Egress deny examples

`NvSecurityRule` manifests that block outbound traffic from pods in `nv-egress-deny`. NeuVector 5.6 is already installed on the Rancher local cluster (`cattle-neuvector-system`); these objects only change policy for the three client Services in that namespace.

Rules are namespace-scoped. `target.policymode: Protect` is what makes a `deny` action drop packets. In Monitor mode the same rule is only a violation. On NeuVector 5.6, `priority` is an integer from 0 to 100 and a higher value is evaluated first. A value outside that range makes the controller reject and delete the object. Implicit deny applies to anything the Protect group does not allow. The broad allow uses the reserved group `external` (everything outside the cluster). Each rule also allows UDP/TCP 53 to the reserved `containers` group so lookups to CoreDNS still succeed. `containers` is selected with criterion `container=*`.

Protect fails closed when the enforcer data path is disconnected: every connection from the group times out, including destinations that have an allow rule. The enforcer log line `DP Connected` means the data path is up.

| File | Behavior |
|------|----------|
| [deny-domain.yaml](deny-domain.yaml) | Deny `example.org` and `*.example.org`. Other external destinations stay allowed. |
| [allow-one-deny-another.yaml](allow-one-deny-another.yaml) | Allow `example.com` and `*.example.com`. Deny `example.net` and `*.example.net`. Other external destinations are denied. |
| [deny-ip-range.yaml](deny-ip-range.yaml) | Deny CIDR `1.1.1.0/24`. Other external destinations stay allowed. |

Address groups take a DNS name, a wildcard name, a CIDR, or a hyphenated range (`10.1.0.1-10.1.0.25`). Several `address` entries on one selector are OR. `address` cannot be combined with other criteria keys. `*` in a value must be quoted in YAML.

`1.1.1.0/24` is Cloudflare's public DNS range and answers on `https://1.1.1.1`, which makes the deny observable. Replace that CIDR before using the file anywhere else. Do not target cluster, node, pod, or service CIDRs.

Custom group names must not start with `nv.`, `fed.`, or `nv.ip.`. Learned group names must be `nv.<service>.<namespace>` and the Service must already exist, or NeuVector deletes the `NvSecurityRule`.

## Apply

```sh
kubectl --kubeconfig local.yaml apply -f neuvector/egress-deny/workloads.yaml
kubectl --kubeconfig local.yaml -n nv-egress-deny rollout status deployment/deny-domain
kubectl --kubeconfig local.yaml -n nv-egress-deny rollout status deployment/allow-deny-domain
kubectl --kubeconfig local.yaml -n nv-egress-deny rollout status deployment/deny-ip-range
kubectl --kubeconfig local.yaml apply -f neuvector/egress-deny/deny-domain.yaml
kubectl --kubeconfig local.yaml apply -f neuvector/egress-deny/allow-one-deny-another.yaml
kubectl --kubeconfig local.yaml apply -f neuvector/egress-deny/deny-ip-range.yaml
neuvector/egress-deny/verify.sh
```

`verify.sh` checks that NeuVector kept the three rules and that Protect mode allows and denies the destinations above.

## Remove

```sh
kubectl --kubeconfig local.yaml delete -f neuvector/egress-deny/deny-domain.yaml
kubectl --kubeconfig local.yaml delete -f neuvector/egress-deny/allow-one-deny-another.yaml
kubectl --kubeconfig local.yaml delete -f neuvector/egress-deny/deny-ip-range.yaml
kubectl --kubeconfig local.yaml delete -f neuvector/egress-deny/workloads.yaml
```

## References

- [CRD — Custom Resource Definitions (SUSE® Security 5.6)](https://documentation.suse.com/cloudnative/security/5.6/en/usingcrd.html) — `address: google.com` egress sample and `priority`
- [Groups (community NeuVector)](https://open-docs.neuvector.com/policy/groups/) — DNS name, wildcard, CIDR, and hyphenated range criteria
- [Network Rules (community NeuVector)](https://open-docs.neuvector.com/policy/networkrules/) — first match wins; deny blocks only in Protect mode
