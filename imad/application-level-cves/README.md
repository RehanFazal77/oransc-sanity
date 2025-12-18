# Near-RT RIC Application-Level CVE Fixes

This directory documents the CVE fixes applied across Near-RT RIC components: **E2**, **E2 Manager**, and **RIC App KPIMON (Go)**.  
Each table lists the CVE number, affected files (clickable), fix details, and a short explanation.

---

## 1. e2

| No. | CVE ID | Affected File | Fix Applied | Explanation |
|:---:|:--------|:---------------|:-------------|:-------------|
| 1 | **CVE-2024-34046** | [`sctpThread.cpp`](./near-rt-ric/e2/sctpThread.cpp) | Added NULL pointer checks before `e2tCounters` increments | Prevents crashes due to dereferencing NULL `peerInfo` pointers during Prometheus metric updates. |
| 2 | **CVE-2024-34045** | [`sctpThread.cpp`](./near-rt-ric/e2/sctpThread.cpp) | Added NULL pointer checks before Prometheus counter increments in E2setup handlers | Prevents segmentation faults when E2setup counters are uninitialized. |
| 3 | **CVE-2024-34044** | [`sctpThread.cpp`](./near-rt-ric/e2/sctpThread.cpp) | Added NULL pointer checks in `buildPrometheusList` and guarded Prometheus initialization calls | Prevents segmentation faults when `peerInfo` or `prometheusFamily` is NULL, ensuring stability. |

---

## 2. e2mgr

| No. | CVE ID | Affected File(s) | Fix Applied | Explanation |
|:---:|:--------|:------------------|:-------------|:-------------|
| 1 | **CVE-2024-34048** | [`e2_node_config_update_notification_handler.go`](./near-rt-ric/e2mgr/e2_node_config_update_notification_handler.go) | Replaced incorrect array indexing `[i]` with `[j]` in inner loops for both GNB and ENB | Prevents out-of-bounds access when updating NodeConfigs, avoiding runtime panics. |
| 2 | **CVE-2024-34047** | [`ric_service_update_handler.go`](./near-rt-ric/e2mgr/ric_service_update_handler.go) | Added array bounds and maximum size checks in `RicServiceUpdateHandler` | Ensures safe indexing of RAN function lists and prevents resource exhaustion. |
| 3 | **CVE-2024-34035** | [`rmr_message_throttler.go`](./near-rt-ric/e2mgr/rmr_message_throttler.go) | Added RMR message throttling with per-RAN rate limits | Prevents denial of service through RMR message flooding by limiting message rate and safely dropping excess messages. |
| 4 | **CVE-2023-42358** | [`rate_limiter.go`](./near-rt-ric/e2mgr/rate_limiter.go), [`timeout.go`](./near-rt-ric/e2mgr/timeout.go), [`http_server.go`](./near-rt-ric/e2mgr/http_server.go) | Implemented HTTP rate limiting and request timeout middleware | Blocks crafted or excessive API requests via per-IP rate limits and timeouts, mitigating DoS through the Subscription Manager API. |

---

## 3. ric-app-kpimon-go

| No. | CVE ID | Affected File | Fix Applied | Explanation |
|:---:|:--------|:---------------|:-------------|:-------------|
| 1 | **CVE-2024-34043** | [`wrapper.c`](./near-rt-ric/ric-app-kpimon-go/wrapper.c) | Added NULL pointer checks for choice union members: `initiatingMessage`, `successfulOutcome`, `unsuccessfulOutcome` | Prevents segmentation faults when processing malformed or partially decoded E2AP-PDU messages. |

---



## 4. submgr

| No. | CVE ID             | Affected File                                                                              | Fix Applied                                                                                                                          | Explanation                                                                                                                                                                |
| :-: | :----------------- | :----------------------------------------------------------------------------------------- | :----------------------------------------------------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
|  1  | **CVE-2024-34036** | [`ratelimiter.go`](./near-rt-ric/submgr/ratelimiter.go), [`control.go`](./near-rt-ric/submgr/control.go) | Added a per-xApp, per-route token-bucket rate limiting system; wrapped all REST and subscription handlers using a RateLimiterWrapper | Prevents malicious xApps from overwhelming submgr with excessive subscription requests, blocking the denial-of-service pathway used to disrupt gNB ↔ RIC connection setup. |

---




## 5. appmgr

| No. | CVE ID                              | Affected File                | Fix Applied                                                                                                            | Explanation                                                                                                                                 |
| :-: | :---------------------------------- | :--------------------------- | :--------------------------------------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------ |
|  1  | **CVE-2024-34073 (AppMgr variant)** | [`restful.go`](./near-rt-ric/appmgr/restful.go) (`parseConfig`) | Added whitelist validation for RMR message types; registration fails if xApp provides unauthorized tx/rx message types | Prevents attackers from registering fake or malicious RMR message types that could disrupt message routing and impact other RIC components. |

---
