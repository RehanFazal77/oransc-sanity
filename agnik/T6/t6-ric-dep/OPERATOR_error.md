# Operator Status and Errors (depRicKubernetesOperator)

This document records **what happened when we tried to use the Kubernetes operator** from the
original `depRicKubernetesOperator/` folder, **why it failed**, and **why the cleaned repo no
longer ships the operator**.

## 1. Initial environment

We tested the operator on server `hpe16` with:

- Ubuntu 22.04
- Kubernetes 1.28.15 (installed via `kubeadm`)
- Containerd as the runtime
- Working kubeconfig at `$HOME/.kube/config` (non-root user)

The Near-RT RIC platform itself was successfully deployed and running **without** the operator.
The issues below are specific to the operator code and Makefile.

---

## 2. `make install`: CRD install problems

### 2.1. Kubeconfig path / permissions

**Symptom:**

```text
error: error loading config file "/root/.kube/config": open /root/.kube/config: permission denied
make: *** [Makefile:113: install] Error 1
```

**Reason:**

- The operator Makefile calls `kubectl` without specifying `KUBECONFIG`, so it tries to use
  `/root/.kube/config` by default.
- We were running as the non-root user `agnikmisra`, and `/root/.kube/config` is not readable.

**Fix applied:**

```bash
KUBECONFIG=$HOME/.kube/config make install
```

This allowed `make install` to run far enough to call `kustomize build config/crd | kubectl apply -f -`.

### 2.2. TLS / certificate verification

After fixing `KUBECONFIG`, we saw:

```text
error: error validating "STDIN": error validating data: failed to download openapi:
Get "https://10.200.105.57:6443/openapi/v2?timeout=32s":
  tls: failed to verify certificate: x509: certificate signed by unknown authority
make: *** [Makefile:113: install] Error 1
```

**Reason:**

- The user kubeconfig contained stale certificate-authority data from a previous cluster.
- After a fresh `kubeadm init`, the new CA did not match the kubeconfig being used.

**Fix applied:**

- Re-copied `/etc/kubernetes/admin.conf` into `$HOME/.kube/config` and fixed permissions.
- Retried with `KUBECONFIG=$HOME/.kube/config make install`.

**Result:**

```text
customresourcedefinition.apiextensions.k8s.io/ricplatforms.ricdeploy.ricplt.com created
```

So **CRD installation succeeded** once kubeconfig was corrected.

---

## 3. `make run`: controller build and tooling errors

Once the CRD was installed, we tried to run the controller with:

```bash
KUBECONFIG=$HOME/.kube/config make run
```

### 3.1. Missing Kubebuilder boilerplate

**Symptom:**

```text
/home/.../bin/controller-gen object:headerFile="hack/boilerplate.go.txt" paths="./..."
open hack/boilerplate.go.txt: no such file or directory
Error: not all generators ran successfully
make: *** [Makefile:53: generate] Error 1
```

**Reason:**

- The project expects a `hack/boilerplate.go.txt` file (standard Kubebuilder layout), but that
  file was missing in the repo snapshot.

**Fix applied:**

- We created a minimal `hack/boilerplate.go.txt` with the Apache 2.0 header.

After adding the boilerplate, `controller-gen` could run and generation succeeded.

### 3.2. Go module / version issues

**Symptom:**

Running `make run` caused `go vet` to complain about the Go version and missing dependencies:

```text
go: go.mod file indicates go 1.20, but maximum version supported by tidy is 1.18
```

**Reason:**

- Ubuntu’s `golang-go` package was Go 1.18, but `go.mod` declared `go 1.20`.

**Fix applied:**

- Installed a newer Go via snap (`go1.25.4`) and ran `go mod tidy` using that binary.
- Copied the updated `go.mod` and `go.sum` back into the repo.

After this, dependency issues were resolved and `go vet` could run.

### 3.3. Undefined API types (core build failure)

Even after fixing boilerplate and modules, `go vet` (and the build) failed with many **undefined
symbol** errors:

```text
# ricdeploy/internal/controller
internal/controller/getClusterRoleBinding.go:9:33: undefined: rbacv1
internal/controller/getCustomResourceDefinition.go:8:39: undefined: unstructured
internal/controller/getEndPoints.go:9:24: undefined: unstructured
internal/controller/getIngress.go:10:22: undefined: unstructured
internal/controller/getJob.go:8:18: undefined: unstructured
internal/controller/getRole.go:7:19: undefined: rbacv1
internal/controller/getRoleBinding.go:7:26: undefined: rbacv1
internal/controller/getStatefulSet.go:8:26: undefined: appsv1
internal/controller/getClusterRoleBinding.go:20:12: too many errors
# [ricdeploy/internal/controller]
vet: internal/controller/getClusterRoleBinding.go:9:33: undefined: rbacv1
make: *** [Makefile:61: vet] Error 1
```

**Reason:**

- The controller code imports `corev1` and `metav1`, but **never imports**:
  - `k8s.io/api/rbac/v1` (for `rbacv1`)
  - `k8s.io/api/apps/v1` (for `appsv1`)
  - `k8s.io/apimachinery/pkg/apis/meta/v1/unstructured` (for `unstructured`)
- Many helper functions (`getClusterRoleBinding.go`, `getStatefulSet.go`, etc.) refer to these
  types directly without the necessary imports or correct package usage.

**Impact:**

- The operator **does not compile** as-is.
- Fixing this would require:
  - Adding the correct imports across multiple files.
  - Verifying that the intended object types match the current Kubernetes APIs.
  - Re-running code generation and re-testing the reconcile logic.

Given the size and spread of these changes, this is **not a quick fix**.

---

## 4. Decision: remove the operator from the cleaned repo

Based on the above:

1. **CRDs can be installed**, but
2. **The controller fails to build and run** due to incomplete/mismatched source code.

The modernization task explicitly said:

> "Next, test the operator. If it's working fine, keep it. If not, see if you can fix. If it's not working, and cannot be fixed, drop it."

We:

- Tried to run `make install` and `make run`.
- Fixed kubeconfig, TLS, boilerplate, and Go module issues.
- Still hit multiple compile-time errors in the controller source.

