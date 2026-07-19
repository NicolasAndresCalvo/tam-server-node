# Decisions, trade-offs & talking points

Notes to back the walkthrough and interview.

## 1. Cross-cloud portability — "how painful to move to Azure?"

Short answer: **the app is trivially portable, the platform layer is not.**

| Layer | Portability | Why |
|---|---|---|
| App + Dockerfile | ✅ moves as-is | It's just a container listening on a port |
| CI build stage | ✅ mostly | Build/push is generic; only the registry auth + push target changes |
| Terraform *structure* | 🟡 reusable shape | Per-concern files (network / registry / runtime / ingress) map 1:1 to Azure |
| Terraform *resources* | ❌ rewrite | `aws_ecs_service` → `azurerm_container_app`, ALB → App Gateway/Front Door, ECR → ACR, SGs → NSGs |

**What I'd do differently to reduce the pain:**
- **Kubernetes (EKS→AKS).** The single biggest portability lever. K8s manifests
  (Deployment/Service/Ingress) are ~90% identical across clouds; only the ingress
  controller + storage classes differ. I chose Fargate here for speed and lower ops on a
  single service, but if multi-cloud were a hard requirement, EKS/AKS with the same Helm
  chart is the answer. Trade-off: more moving parts, higher baseline cost/ops.
- **Keep the compute inputs cloud-agnostic** (variables like `container_port`,
  `desired_count`, image tag) so swapping the runtime resources is the only change.
- **Terraform, not CloudFormation/ARM** — one tool, one workflow across both clouds.
- **OICD federation instead of cloud-specific secrets**, so the CI/CD auth pattern is the
  same shape on GitHub→AWS and GitHub→Azure.

The honest version: containerizing bought us app portability for free; true infra
portability costs either a rewrite of the runtime module or adopting Kubernetes up front.

## 2. Observability (not wired in the app, but the plan)

- **Logs:** container stdout → `awslogs` driver → CloudWatch Logs (14-day retention). In
  prod I'd ship to a central sink (OpenSearch / Loki / Datadog) with structured JSON logs.
- **Metrics:** Container Insights is enabled on the cluster → CPU/mem/task counts. ALB
  emits request count, latency, 5xx, healthy-host count out of the box.
- **App-level:** add a `/metrics` Prometheus endpoint (prom-client) scraped by AMP or an
  agent; RED metrics (rate/errors/duration) on the HTTP handler.
- **Tracing:** OpenTelemetry SDK in the app → ADOT collector sidecar → X-Ray / Tempo.
- **Alerting:** CloudWatch alarms on ALB 5xx rate, target 4xx, unhealthy hosts,
  task CPU/mem, → SNS/PagerDuty. SLO: p99 latency + availability on `/health`.

## 3. Deliberate trade-offs

| Chose | Over | Because | Cost |
|---|---|---|---|
| Fargate | EKS | Speed, no node ops for one service | Less portable, per-task pricing |
| Single NAT GW | 1 NAT/AZ | Cost (~$33 vs ~$66/mo) | NAT is a single-AZ SPOF for egress |
| Single NAT GW | VPC endpoints | Simpler to read | Endpoints are more secure + can drop NAT |
| ALB | NLB | L7 routing, host/path rules, native TLS | Slightly higher cost |
| `ignore_changes` on task def image | TF owns image | CD ships images, TF owns infra — no fight | Two systems touch the service |
| S3 backend + native lockfile | Local state | Team-safe remote state, no DynamoDB (TF ≥ 1.10 `use_lockfile`) | Bucket must be bootstrapped out-of-band |
| Flat Terraform (one root module) | Module tree | Small stack reads more directly; less indirection | Fewer reuse seams; portability arg shifts from module swap to file swap |

## 4. Cost levers (full model in `pricing.md`)

- `desired_count = 1` → −~$10/mo (drops HA).
- Tasks in **public** subnets + `assign_public_ip`, drop NAT → −~$35/mo, weaker network story.
- **VPC interface endpoints** (ecr.api, ecr.dkr, logs) + S3 gateway endpoint → drop NAT,
  *better* security posture, roughly cost-neutral.
- Stand up the day before the interview, `terraform destroy` after → under a dollar total.
- Numbers and the per-resource breakdown live in [`pricing.md`](pricing.md).

## 5. Security posture summary

- No public IPs on compute; ALB is the only ingress.
- SG-to-SG rule (ALB→task), not CIDR — least privilege at the network layer.
- Non-root container, read-only root FS, scan-on-push ECR.
- OIDC short-lived creds; CI role scoped to one repo, one ECR repo, one ECS service.
- TLS 1.2/1.3, HTTP→HTTPS redirect, ACM-managed (auto-renew).
- Next hardening: WAF on the ALB, VPC endpoints, secrets via Secrets Manager + task-role
  read, image signing (cosign), private image scanning gate in CI.
