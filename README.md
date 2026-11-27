# 🚀 DevOps Tech Challenge 2: GitOps CI/CD to an Autoscaling EKS Cluster

An end-to-end project that deploys a Node.js/Express app to **Amazon EKS** through **two CI/CD approaches** (Jenkins, and GitHub Actions + Argo CD), then hardens the platform for production and **tests it under failure**: broken releases, node drains, pod kills, and outages, all under live traffic.

## ✅ What This Project Demonstrates

- **Modular Terraform** (network, EKS, add-on IAM) with **remote state in S3** and native state locking
- A **bootstrap stack** for long-lived resources, separate from the cluster stack that gets created and destroyed
- Packaging an app with **Helm**: probes, resource requests, Ingress, HPA, PDB, topology spread, locked-down security context
- Two CI/CD approaches: **push-based** (Jenkins) vs **pull-based GitOps** (GitHub Actions + Argo CD)
- Keyless AWS access everywhere: **GitHub OIDC** for CI and **EKS Pod Identity** for cluster add-ons
- **Security checks in CI**: Terraform fmt/validate and a blocking **Trivy** scan with reviewed, documented exceptions
- Pod and node autoscaling (**HPA + Cluster Autoscaler**)
- Monitoring and alerting with **Prometheus, Grafana, and Alertmanager → Slack**
- Failure testing under live traffic, and real troubleshooting

## 🏗️ Architecture

```
                  GitHub (source of truth)
                     │            ▲
          push app/**│            │ commit new image tag
                     ▼            │
             GitHub Actions ──────┘──► Amazon ECR
             (OIDC, no stored keys)        │
                                           │ pull image
  Argo CD (in cluster) ── syncs from Git ──┼──────────────┐
                                           ▼              ▼
  Users ──► ALB ──► Ingress ──►  Pods (AZ a)        Pods (AZ b)
                                  │                       │
             Prometheus ◄─────────┴── metrics ────────────┘
                  │
             Alertmanager ──► Slack
```

| Branch | CI/CD approach | Namespace |
|---|---|---|
| `main` | Jenkins: build → push to ECR → Helm deploy | `default` |
| `production-upgrade` | GitHub Actions (CI) + Argo CD (CD) | `gitops` |

## 📁 Repository Structure

```
├── bootstrap/                 # Long-lived: state bucket, ECR, GitHub OIDC provider + CI role
├── terraform/                 # The cluster stack: created and destroyed as needed
│   ├── main.tf                # Wires the modules together
│   ├── terraform.tfvars.example
│   └── modules/
│       ├── network/           # VPC, subnets, NAT, route tables, security group
│       ├── eks/               # Cluster, node group, their IAM roles, KMS key for Secrets
│       └── addon-iam/         # Pod Identity roles for the Load Balancer Controller and Cluster Autoscaler
├── scripts/install-addons.sh  # Installs cluster add-ons with pinned versions
├── app/                       # Node.js app + Dockerfile
├── app-chart/                 # Helm chart
├── argocd/                    # Argo CD Application
├── monitoring/                # Alert rules and Alertmanager config
├── jenkins/ + Jenkinsfile     # Local Jenkins pipeline
└── .github/workflows/         # CI (build/push) and Terraform checks
```

## 0️⃣ Bootstrap Stack (one time)

**Why?** Some resources need to outlive the cluster. When they live alongside the cluster, or get created by hand, a teardown deletes them, and CI breaks the next time it runs. The bootstrap stack holds them separately, and they're protected from deletion.

```bash
cd bootstrap
terraform init
terraform apply
```

| Resource | Why |
|---|---|
| **S3 state bucket** | Remote state for both stacks. Versioned, encrypted, private, HTTPS-only, and `prevent_destroy`. Locking uses S3 natively (`use_lockfile`), so no DynamoDB table is needed |
| **ECR repository** | Imported from an existing repo. **Immutable tags** (a commit SHA can never be overwritten), **scan on push**, and a lifecycle policy that keeps only recent images |
| **GitHub OIDC provider + CI role** | Lets GitHub Actions log in to AWS with short-lived tokens. The trust policy only accepts this repo on the `production-upgrade` branch; the role can only push to this one ECR repo |

The bootstrap's own state was created locally first, then migrated into the bucket it created.

## 1️⃣ Provision the Cluster with Terraform

**Why?** Building the cluster as code makes it repeatable, reviewable, and easy to tear down.

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # then set your own public IP as a /32
terraform init
terraform plan     # review exactly what will be created
terraform apply
aws eks update-kubeconfig --region us-east-1 --name devops-challenge2-cluster
kubectl get nodes
```

| Resource | Why |
|---|---|
| **VPC across 2 AZs** (`10.1.0.0/16`) | Public subnets hold the ALB and NAT; private subnets hold the worker nodes so they're never exposed directly. Subnet ranges are calculated with `cidrsubnet()`, and subnets are tagged so the ALB controller knows where to place load balancers |
| **NAT gateway** (`single_nat_gateway` toggle) | `true`: one NAT to keep cost down. `false`: one NAT and route table per AZ, removing the single point of failure for production |
| **EKS cluster (Kubernetes 1.36)** | The managed control plane. The API endpoint only accepts traffic from the IP in `terraform.tfvars`, and a validation rule rejects `0.0.0.0/0` |
| **KMS key for Secrets** | Envelope encryption for Kubernetes Secrets with a customer-managed key, with yearly rotation. The cluster role can use only this key |
| **Managed node group** | t3.small, **min 2 / max 4**, in private subnets, `max_unavailable = 1`. Terraform ignores `desired_size` so it doesn't fight the Cluster Autoscaler |
| **Pod Identity roles** | Least-privilege roles for the add-ons. The Cluster Autoscaler can only resize node groups tagged as owned by this cluster |

## 2️⃣ Install the Cluster Add-ons

**Why?** Some cluster features need controllers running inside the cluster.

```bash
./scripts/install-addons.sh
```

| Add-on | Why |
|---|---|
| **EKS Pod Identity agent** (Terraform) | Gives add-on pods their own IAM roles, with no stored keys and no per-cluster OIDC setup |
| **AWS Load Balancer Controller** | Reads the Ingress and creates the ALB |
| **metrics-server** | Supplies the CPU and memory numbers the HPA needs |
| **Cluster Autoscaler** | Adds nodes when pods can't fit and removes idle ones. Image pinned to match the Kubernetes version |
| **kube-prometheus-stack** | Prometheus, Grafana, and Alertmanager for monitoring |

Chart versions are pinned, so a fresh install behaves the same every time. When the Load Balancer Controller's version was pinned, its IAM policy was checked against the official policy for that release.

## 3️⃣ Containerize the App

**Why?** A container packages the app with its dependencies so it runs the same everywhere.

```bash
docker build --platform linux/amd64 -t hello-app ./app
```

- **`node:22-alpine`**: a supported Node.js version that still receives security patches
- **`npm ci --omit=dev`**: exact versions from the lock file, without dev dependencies
- **`USER node`**: the app runs as a non-root user

**Why `--platform linux/amd64`?** Jenkins builds on an ARM Mac, but the EKS nodes are amd64. Without the flag, the image won't run on the nodes.

## 4️⃣ Package the App with Helm

**Why?** One Helm chart describes everything the app needs to **run, be reached, scale, and stay protected**.

| Piece | Setting | Why |
|---|---|---|
| **Deployment** | Readiness and liveness probes; requests `400m` CPU / `128Mi` | Readiness keeps pods out of traffic until they're ready; liveness restarts stuck containers; requests tell Kubernetes how much room each pod needs |
| **Security context** | Non-root, read-only root filesystem, no privilege escalation, all Linux capabilities dropped, `RuntimeDefault` seccomp | If the app were ever compromised, the attacker can't write to disk, gain root, or use risky system calls |
| **Service** | ClusterIP on port 3000 | A permanent address for the pods inside the cluster |
| **Ingress** | ALB, `internet-facing`, `target-type: ip` | The Load Balancer Controller builds one ALB that sends traffic straight to pod IPs |
| **HPA** | 2 to 12 replicas at 50% CPU and memory | Adds pods as load grows; the Cluster Autoscaler adds nodes when pods don't fit |
| **Pod Disruption Budget** | `minAvailable: 1` | Node drains can never evict the last running pod |
| **Topology spread** | Across zones, with `matchLabelKeys: [pod-template-hash]` | Keeps replicas in different zones, even during rolling updates |
| **values.yaml** | Image tag = commit SHA | Nothing is hardcoded; every deploy is a real, traceable change |

## 5️⃣ Pipeline 1: Jenkins (push-based)

**Why?** A traditional pipeline that builds and deploys from outside the cluster.

| Stage | What it does | Why |
|---|---|---|
| **Trigger** | `pollSCM('H/5 * * * *')` | Jenkins runs locally on my Mac, so GitHub can't reach it with a webhook; polling checks for new commits every 5 minutes instead |
| **Build** | `docker build --platform linux/amd64`, tagged with the build number | Matches the node platform; the build number makes each release traceable |
| **Push** | Logs in to ECR with a short-lived token and pushes | Nodes pull images from ECR |
| **Deploy** | `helm upgrade --install --wait --timeout 5m`, then `kubectl rollout status` | If the new pods never become healthy, the **build fails instead of the release going live** |
| **Post** | Logs out of ECR | Doesn't leave registry credentials behind |

Jenkins is configured as a **Pipeline script from SCM** job pointing at the `Jenkinsfile` in this repo.

## 6️⃣ Pipeline 2: GitOps with GitHub Actions + Argo CD (pull-based)

**Why?** In GitOps, **Git is the single source of truth.** The CI pipeline never touches the cluster; Argo CD runs **inside** the cluster and **pulls** changes from Git, so nothing outside needs cluster access.

**The flow:**
1. A push that changes `app/**` triggers GitHub Actions.
2. Actions logs in to AWS with **OIDC**: GitHub issues a short-lived token, and the IAM role's trust policy only accepts tokens from this repo and branch, matched on GitHub's immutable owner and repo IDs. AWS returns temporary credentials, so there are **no stored keys to leak or rotate**.
3. Builds the image for amd64 and pushes it to ECR, tagged with the **commit SHA**.
4. Commits the new tag into `app-chart/values.yaml` (`[skip ci]` prevents a loop).
5. **Argo CD** sees the change and syncs the cluster.

**Argo CD settings:**
- **Auto-sync:** applies new commits automatically
- **Prune:** removes resources deleted from Git
- **Self-heal:** undoes manual changes in the cluster, so it always matches Git

**Why this matters:** every change is a reviewed commit, and **rollback is just a `git revert`**.

## 🔒 Security Checks in CI

A second workflow (`.github/workflows/terraform.yml`) runs on every change to Terraform. It needs **no AWS credentials** and has read-only repo permissions.

| Check | Why |
|---|---|
| `terraform fmt -check` and `validate` on both stacks | Catches formatting drift, typos, and broken module wiring before anything is applied |
| **Trivy IaC scan** (blocking on HIGH/CRITICAL) | Scans Terraform, Dockerfiles, and the Helm chart for misconfigurations. The action is pinned to an immutable release, since mutable tags were hijacked in a 2026 supply-chain attack |

The first scan found 13 findings. Most were **fixed** (non-root containers, locked-down security context, no public IPs on public subnets, KMS for Secrets, API restricted to one IP). The rest are **accepted with a written reason** in `.trivyignore.yaml`:

| Finding | Why it's accepted | Plan to remove it |
|---|---|---|
| Public EKS API endpoint | kubectl and Helm run from a laptop with no VPN or bastion; access is limited to one /32 | Private-only endpoint with an SSM bastion or VPN |
| Node security group allows all egress | Nodes need ECR, AWS APIs, GitHub, and Slack through the NAT | VPC endpoints for ECR, S3, STS, and CloudWatch |
| State bucket uses SSE-S3, not a customer-managed key | Private, TLS-only, and versioned; a CMK adds cost and complexity with little gain here | Revisit if compliance requires it |
| Local Jenkins runs as root | Needs the Docker socket; it's a local learning setup and isn't deployed | Run as the `jenkins` user with docker group access |

## 7️⃣ Monitoring and Alerting

**Why?** To find out about problems **before users report them**.

| Piece | What it does |
|---|---|
| **Prometheus** | Collects metrics and evaluates alert rules |
| **Alert rule `HelloAppDown`** | Fires when available app pods stay **below 1 for a full minute** (`for: 1m` filters out short blips) |
| **Alertmanager** | Routes `HelloApp` alerts to Slack, waits 30 seconds to group related alerts, and sends a "resolved" message when fixed |
| **Slack webhook** | Stored in a **Kubernetes Secret**, encrypted with the cluster's KMS key, never in the config or Git |
| **Grafana** | Dashboards showing usage and capacity |

**Grafana finding:** at idle, the app used only a small fraction of its requested CPU and memory, so requests can be right-sized after load testing.

## 8️⃣ Failure Testing

**Why?** A deployment that works isn't the same as a platform that **fails safely**. Each test ran while a steady stream of HTTP requests hit the app through the ALB, with every response logged.

| Test | How | What it validates |
|---|---|---|
| **Broken release** | Pushed an image tag that doesn't exist through Git | New pods never become Ready, so they never get traffic; old pods keep serving. Rollback through `git revert` |
| **Node drain** | Drained a node running the app, before and after adding topology spread, the PDB, and 2 minimum replicas | Maintenance doesn't take the app down |
| **Pod kill** | Deleted a running pod | Kubernetes replaces it while the remaining pods keep serving |
| **Time to detect** | Scaled the app to 0 | The outage alert reaches Slack, followed by a "resolved" message |

**Key takeaway:** Kubernetes only replaces old pods when new ones pass their readiness probe, so a broken release never reaches users. But Kubernetes doesn't roll back on its own; **the rollback came from Git**.

## 🛠️ Troubleshooting (Issues Hit While Building)

| Problem | Cause | Fix |
|---|---|---|
| **Both pods landed on one node**, so a node drain caused failed requests | Anti-affinity was only *preferred* (a suggestion). Topology spread then counted **old** pods during rolling updates and put both new pods in one zone | Added `matchLabelKeys: [pod-template-hash]` so only pods from the same rollout are counted. Chose this over *required* anti-affinity, which would cap pods at one per node and block the HPA from reaching 12 |
| **CI role missing after a teardown** | The GitHub OIDC provider and CI role had been created outside the cluster's lifecycle and were deleted | Moved them into the bootstrap stack in Terraform, so they're versioned and survive cluster teardowns |
| **GitHub Actions couldn't assume its role** | GitHub's OIDC `sub` includes immutable owner/repo IDs that didn't match the trust policy | Decoded and printed the token's claims, then matched the trust policy to the exact value |
| **Load Balancer Controller policy out of date** | Pinning the controller to v3.7.0 required a permission the old IAM policy didn't have | Diffed the policy against the official one for that release and updated it |
| **Slack alert never arrived** | The alert was firing in Grafana, so Prometheus worked; Alertmanager logs showed "unsupported protocol scheme" because the Secret was **empty** | Recreated the Secret from a temporary file, deleted the file, and retested: the alert arrived |
| **Pod Pending with "Too many pods"** | A t3.small allows only 11 pods, since each pod takes a VPC IP. The autoscaler can't help DaemonSet pods | Cordoned the full node and rescheduled one controller replica. Long-term: larger instances or VPC CNI prefix delegation |
| **HPA showed `<unknown>`** | Pods had no resource requests, so utilization couldn't be calculated | Added requests to the chart |

## 🧠 Lessons Learned

- **A config that looks right isn't proven until you test it under failure.**
- **Readiness gates protect users; Git gives you the rollback.**
- **Print the real value instead of assuming** (the OIDC `sub` claim).
- **Test alerts end to end**, not just the rule.
- **Separate what lives forever from what gets torn down.**
- **Upgrading a controller means upgrading its permissions too.**

## ➡️ Next Steps

- **Container image scanning** with Trivy in the build pipeline, and `npm test`
- **Canary releases with Argo Rollouts** for automatic rollback on bad metrics
- A pre-merge check that the image tag **exists in ECR**
- **Graceful shutdown** (handle `SIGTERM`) in the app
- **VPC endpoints** to cut internet egress, and a **private-only API endpoint**
- Manage the add-on installs through **Argo CD** (app-of-apps) instead of a script
- **One NAT gateway per AZ** for production (`single_nat_gateway = false`)

## 🧹 Teardown

Delete Kubernetes-created AWS resources first: ALBs made by the Load Balancer Controller aren't managed by Terraform and will block the VPC from being deleted.

```bash
kubectl delete -f argocd/application.yaml
helm uninstall hello-app
kubectl delete namespace gitops
# wait until no k8s- load balancers remain:
aws elbv2 describe-load-balancers --query "LoadBalancers[?contains(LoadBalancerName,'k8s-')].LoadBalancerName"
helm uninstall monitoring -n monitoring
helm uninstall aws-load-balancer-controller -n kube-system
helm uninstall cluster-autoscaler -n kube-system
helm uninstall metrics-server -n kube-system
cd terraform && terraform destroy
```

The **bootstrap stack stays**: the state bucket, ECR repo, and CI role are protected with `prevent_destroy`, so the next spin-up and the CI pipeline keep working. The KMS key waits 7 days before it's fully deleted.
