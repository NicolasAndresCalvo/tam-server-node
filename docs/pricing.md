# Pricing model

Cost model for this stack in **eu-west-1 (Ireland)**, on-demand pricing, no
savings plans. Figures are rounded monthly estimates for a low-traffic single
service; they move with traffic (ALB LCUs, NAT data, log volume) but the fixed
hourly components dominate at this scale.

## What actually costs money

The bill is driven by three always-on hourly resources (NAT, ALB, Fargate).
Everything else is rounding error at this traffic level.

```
NAT Gateway   ████████████████████  ~$35/mo   hourly + $0.048/GB processed
ALB           ██████████            ~$18/mo   hourly + LCUs (~$6 at low load)
Fargate x2    ███████████           ~$20/mo   0.25 vCPU + 0.5 GB per task
Logs+Insights █                     ~$2/mo    ingest + Container Insights metrics
ECR + Route53 ▏                     ~$1/mo    <0.5 GB images; zone already exists
```

## Breakdown (24/7)

| Component | Unit price (eu-west-1) | Qty | ~Monthly |
|---|---|---|---|
| NAT Gateway | $0.048/hr + $0.048/GB | 1 × 730 hr | **$35** |
| Application Load Balancer | $0.0252/hr + LCU $0.008/hr | 1 × 730 hr + low LCU | **$18–24** |
| Fargate task | 0.25 vCPU × $0.04456 + 0.5 GB × $0.004865 /hr | 2 × 730 hr | **$20** |
| CloudWatch Logs + Container Insights | $0.57/GB ingest + metrics | low volume | **~$2** |
| ECR storage | $0.10/GB-mo | ~0.5 GB (10 images) | **~$0.05** |
| Route53 hosted zone | $0.50/mo | shared w/ existing zone | **~$0** |
| Data transfer out | first 100 GB/mo free | demo traffic | **~$0** |
| **Total** | | | **≈ $75–80/mo** |

Route53's hosted zone for `nicolasandrescalvo.com` already exists in this account
(shared with the portfolio site), so it adds no marginal cost here.

## Demo cost (the way it's actually run)

The app isn't left running. Stand it up shortly before the interview and
`terraform destroy` after:

```
Hourly burn ≈ NAT $0.048 + ALB $0.025 + 2×Fargate $0.027 ≈ $0.10/hr
```

A few hours live → **under $1 total**. This is why there's a `destroy` action in
the Terraform workflow.

## Cost levers

| Lever | Saving | Trade-off |
|---|---|---|
| `desired_count = 1` | −~$10/mo | Drops HA (single task) |
| **VPC interface endpoints** (ecr.api, ecr.dkr, logs) + S3 gateway → drop NAT | −~$35/mo, roughly cost-neutral after endpoint hours | *Better* security posture; a bit more Terraform |
| Tasks in public subnets + `assign_public_ip`, drop NAT | −~$35/mo | Weaker network story, public IPs on compute |
| NLB instead of ALB | small | Lose L7 routing + native ACM termination |
| Fargate Spot | up to −70% on compute | Tasks can be reclaimed; fine for stateless HTTP |

The single highest-leverage change is replacing the NAT Gateway with **VPC
endpoints** — it removes the biggest line item *and* improves the security
posture (no internet egress path from the tasks at all). It's listed as the next
hardening step rather than shipped here to keep the first version simple.

## Notes on scaling

- **Traffic up:** ALB LCUs and NAT data-processing grow with request/byte volume;
  Fargate cost grows with `desired_count` (or autoscaling target).
- **Environments:** a second env (staging) roughly doubles the fixed hourly cost.
  Sharing one NAT/ALB across envs via path/host routing is the lever there.
- See [`decisions.md`](decisions.md) for the reasoning behind these trade-offs.
