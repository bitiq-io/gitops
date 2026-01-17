# bootstrap-operators

Helm chart that manages OLM Subscriptions for cluster-wide operators.

## OpenShift AI (RHOAI) operator discovery

Do not assume the package/channel blindly. Verify the available channels and
current CSV in the target cluster before pinning values.

```bash
# Discover packages
oc get packagemanifest -n openshift-marketplace | rg -i 'rhods|opendatahub|openshift.*ai'

# Inspect channels + currentCSV (example: rhods-operator)
oc get packagemanifest rhods-operator -n openshift-marketplace \
  -o jsonpath='{range .status.channels[*]}{.name}{"\t"}{.currentCSV}{"\n"}{end}'
```

Default intent is the `fast-3.x` channel for OpenShift AI 3.x, but confirm this
matches the cluster catalog before enabling.

Enable via values:

```yaml
operators:
  openshiftAI:
    enabled: true
    channel: fast-3.x
    name: rhods-operator
    source: redhat-operators
    sourceNamespace: openshift-marketplace
    installNamespace: openshift-operators
    approval: Automatic
```
