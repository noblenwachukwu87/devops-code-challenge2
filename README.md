# 🚀 DevOps Tech Challenge 2: GitOps CI/CD to an Autoscaling EKS Cluster

An end-to-end project that deploys a Node.js/Express app to **Amazon EKS** through **two CI/CD approaches** (Jenkins, and GitHub Actions + Argo CD), then hardens the platform for production and **tests it under failure**: broken releases, node drains, pod kills, and outages, all under live traffic.

## ✅ What This Project Demonstrates

- Infrastructure as Code with Terraform (VPC, EKS, node group, IAM)
- Packaging an app with **Helm**: probes, resource requests, Ingress, HPA, PDB, topology spread
- Two CI/CD approaches: **push-based** (Jenkins) vs **pull-based GitOps** (GitHub Actions + Argo CD)
- Keyless AWS access from CI with **OIDC**
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
| `gitops` / `production-upgrade` | GitHub Actions (CI) + Argo CD (CD) | `gitops` |

## 1️⃣ Provision the Infrastructure with Terraform

**Why?** Building the cluster as code makes it repeatable, reviewable, and easy to tear down.

```bash
cd terraform
terraform init
terraform plan     # review exactly what will be created
terraform apply
aws eks update-kubeconfig --region us-east-1 --name devops-challenge2-cluster
kubectl get nodes
```

| Resource | Why |
|---|---|
| **VPC across 2 AZs** (`10.1.0.0/16`) | Public subnets hold the ALB; private subnets hold the worker nodes so they're never exposed directly. Subnets are tagged so the ALB controller knows where to place load balancers. |
| **Single NAT gateway** | Lets private nodes reach the internet (to pull images) while keeping cost down. Tradeoff: one per AZ would remove a single point of failure in production. |
| **EKS cluster (Kubernetes 1.36)** | The managed Kubernetes control plane. |
| **Managed node group** | t3.small, **min 2 / max 4**, in private subnets, `max_unavailable = 1` so node updates replace one node at a time. |
| **IAM roles** | Separate roles for the control plane and worker nodes, including ECR read-only access so nodes can pull images. |

## 2️⃣ Install the Cluster Add-ons

**Why?** Some cluster features need controllers running inside the cluster. These were installed with Helm.

| Add-on | Why |
|---|---|
| **IAM OIDC provider** | Lets Kubernetes service accounts assume IAM roles (IRSA), so add-ons get AWS permissions without stored keys |
| **AWS Load Balancer Controller** | Reads the Ingress and creates the ALB |
| **metrics-server** | Supplies CPU and memory numbers the HPA needs |
| **Cluster Autoscaler** | Adds nodes when pods can't fit, removes idle ones |
| **kube-prometheus-stack** | Prometheus, Grafana, and Alertmanager for monitoring |

```bash
eksctl utils associate-iam-oidc-provider --cluster devops-challenge2-cluster --region us-east-1 --approve
helm install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system ...
helm install metrics-server metrics-server/metrics-server -n kube-system
helm install cluster-autoscaler autoscaler/cluster-autoscaler -n kube-system ...
```

## 3️⃣ Containerize the App

**Why?** A container packages the app with its dependencies so it runs the same everywhere.

```bash
docker build --platform linux/amd64 -t hello-app ./app
```

**Why `--platform linux/amd64`?** Jenkins builds on an ARM Mac, but the EKS nodes are amd64. Without the flag, the image won't run on the nodes.

## 4️⃣ Package the App with Helm

**Why?** One Helm chart describes everything the app needs to **run, be reached, scale, and stay protected**.

| Piece | Setting | Why |
|---|---|---|
| **Deployment** | Readiness and liveness probes; requests `400m` CPU / `128Mi` | Readiness keeps pods out of traffic until they're ready; liveness restarts stuck containers; requests tell Kubernetes how much room each pod needs |
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
2. Actions logs in to AWS with **OIDC**: GitHub issues a short-lived token, and the IAM role's trust policy only accepts tokens from this repo and branch. AWS returns temporary credentials, so there are **no stored keys to leak or rotate**.
3. Builds the image for amd64 and pushes it to ECR, tagged with the **commit SHA**.
4. Commits the new tag into `app-chart/values.yaml` (`[skip ci]` prevents a loop).
5. **Argo CD** sees the change and syncs the cluster.

**Argo CD settings:**
- **Auto-sync:** applies new commits automatically
- **Prune:** removes resources deleted from Git
- **Self-heal:** undoes manual changes in the cluster, so it always matches Git

**Why this matters:** every change is a reviewed commit, and **rollback is just a `git revert`**.

## 7️⃣ Monitoring and Alerting

**Why?** To find out about problems **before users report them**.

| Piece | What it does |
|---|---|
| **Prometheus** | Collects metrics and evaluates alert rules |
| **Alert rule `HelloAppDown`** | Fires when available app pods stay **below 1 for a full minute** (`for: 1m` filters out short blips) |
| **Alertmanager** | Routes `HelloApp` alerts to Slack, waits 30 seconds to group related alerts, and sends a "resolved" message when fixed |
| **Slack webhook** | Stored in a **Kubernetes Secret**, never in the config or Git |
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
| **GitHub Actions couldn't assume its role** | GitHub's OIDC `sub` includes immutable owner/repo IDs that didn't match the trust policy | Decoded and printed the token's claims, then matched the trust policy to the exact value |
| **Slack alert never arrived** | The alert was firing in Grafana, so Prometheus worked; Alertmanager logs showed "unsupported protocol scheme" because the Secret was **empty** | Recreated the Secret from a temporary file, deleted the file, and retested: the alert arrived |
| **Pod Pending with "Too many pods"** | A t3.small allows only 11 pods, since each pod takes a VPC IP. The autoscaler can't help DaemonSet pods | Cordoned the full node and rescheduled one controller replica. Long-term: larger instances or VPC CNI prefix delegation |
| **HPA showed `<unknown>`** | Pods had no resource requests, so utilization couldn't be calculated | Added requests to the chart |
| **No IAM OIDC provider** | The cluster's OIDC issuer wasn't registered with IAM | `eksctl utils associate-iam-oidc-provider` |

## 🧠 Lessons Learned

- **A config that looks right isn't proven until you test it under failure.**
- **Readiness gates protect users; Git gives you the rollback.**
- **Print the real value instead of assuming** (the OIDC `sub` claim).
- **Test alerts end to end**, not just the rule.

## ➡️ Next Steps

- Add **`npm test`** and **Trivy** image scanning to the pipelines
- **Canary releases with Argo Rollouts** for automatic rollback on bad metrics
- A pre-merge check that the image tag **exists in ECR**
- **Graceful shutdown** (handle `SIGTERM`) in the app
- Manage cluster add-ons **as code**
- **One NAT gateway per AZ** for production

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
cd terraform && terraform destroy
```
