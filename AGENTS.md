# TY Multiverse Root Agent Notes

## Jenkins Access

- Jenkins base URL:
  - `https://tymultiverse.cc/jenkins/`
- Jenkins is also reachable from Kubernetes after `ssh oke-node`
  - namespace: `default`
  - pod label path: `deploy/jenkins`
  - current service: `jenkins-service`
  - current pod seen during investigation: `jenkins-7d5dbc864-ljn9t`
- Jenkins-related deployment work can use the frontend deploy job:
  - Folder: `vinskao`
  - Job: `ty-multiverse-frontend-deploy`
- The user has an API trigger token for Jenkins automation.
  - Token is stored locally in `.env.jenkins` (gitignored) — see that file for the actual value.

## How To Use Later

- If Jenkins webhook or auto-build does not fire, prefer trying an API-triggered build before doing manual pod hotfixes.
- Expected use case:
  - trigger frontend rebuild/deploy so Astro emits a new hashed client bundle
  - avoid relying on in-pod edits for immutable cached JS assets
- First trigger path to try next time:
  - `/jenkins/job/vinskao/job/ty-multiverse-frontend-deploy/build?token=<JENKINS_API_TOKEN>`
  - replace `<JENKINS_API_TOKEN>` with the value from `.env.jenkins`
  - if the job is parameterized, try the corresponding `buildWithParameters` form
- Useful K8s entry points:
  - `ssh oke-node 'kubectl get pods -A | grep -i jenkins'`
  - `ssh oke-node 'kubectl exec deploy/jenkins -- ...'`
  - `ssh oke-node 'kubectl get svc -A | grep -i jenkins'`

## Current Caveat

- The token alone does not guarantee success unless the exact Jenkins trigger endpoint and job configuration match.
- If API triggering is needed again, verify:
  - the Jenkins base URL or context path
  - whether the job uses `build`, `buildWithParameters`, or tokenized trigger routing
  - whether CSRF crumb handling is still required for that endpoint

---

## Terraform 部署流程

```bash
terraform init
cp terraform.tfvars.example terraform.tfvars
# 編輯 terraform.tfvars：ssh key 路徑、bastion_allowed_cidrs、operator_await_cloudinit
terraform plan
terraform apply
```

### 取得常用資訊
```bash
terraform output -raw kubeconfig > kubeconfig
export KUBECONFIG=kubeconfig
kubectl get nodes
kubectl get pods --all-namespaces

terraform output -raw ssh_to_bastion
terraform output -raw ssh_to_operator
terraform output -raw bastion_public_ip
terraform output -raw apiserver_private_host
```

### 銷毀資源
```bash
terraform destroy
terraform destroy -auto-approve
```

## OCI Session Token 管理

```bash
oci session validate --profile peoplesystem-v2
oci session authenticate --profile-name peoplesystem-v2 --region ap-singapore-2
oci session refresh --profile peoplesystem-v2
```

## Object Storage（獨立 Terraform root）

```bash
cd peoplesystem-terraform-oke/object-storage
cp terraform.tfvars.example terraform.tfvars
# 填入 oci_config_profile / region / compartment_id / bucket_name

terraform init
terraform fmt -check && terraform validate
terraform plan -out=tfplan
terraform apply tfplan

terraform output -raw bucket_name
terraform output -raw bucket_namespace

# 驗證 bucket 存在
oci os bucket get \
  --profile peoplesystem-v2 \
  --namespace "$(terraform output -raw bucket_namespace)" \
  --bucket-name "$(terraform output -raw bucket_name)"

# 上傳測試檔
echo "hello" > /tmp/test.txt
oci os object put \
  --profile peoplesystem-v2 \
  --namespace "$(terraform output -raw bucket_namespace)" \
  --bucket-name "$(terraform output -raw bucket_name)" \
  --name test/test.txt --file /tmp/test.txt

# 列出並刪除測試檔
oci os object list --profile peoplesystem-v2 \
  --namespace "$(terraform output -raw bucket_namespace)" \
  --bucket-name "$(terraform output -raw bucket_name)" --prefix test/
oci os object delete --profile peoplesystem-v2 \
  --namespace "$(terraform output -raw bucket_namespace)" \
  --bucket-name "$(terraform output -raw bucket_name)" \
  --object-name test/test.txt
```

## Ingress NGINX + cert-manager

```bash
# 清理 demo 測試 namespace
kubectl delete namespace demo --ignore-not-found

# 安裝 ingress-nginx（固定 IP）
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set controller.service.loadBalancerIP=$(terraform output -raw service_lb_reserved_ip_address) \
  --set controller.admissionWebhooks.objectSelector.matchExpressions[0].key=acme.cert-manager.io/http01-solver \
  --set controller.admissionWebhooks.objectSelector.matchExpressions[0].operator=DoesNotExist

kubectl -n ingress-nginx get svc ingress-nginx-controller -w

# 安裝 cert-manager
helm repo add jetstack https://charts.jetstack.io
helm repo update
kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --set crds.enabled=true

# 建立 ClusterIssuer
cat <<'YAML' | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-http01
spec:
  acme:
    email: tianyikao@gmail.com
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: le-account-key
    solvers:
    - http01:
        ingress:
          class: nginx
YAML

# 若簽發卡在 pending（webhook 問題）
kubectl patch validatingwebhookconfiguration ingress-nginx-admission \
  --type='json' -p='[{"op":"replace","path":"/webhooks/0/failurePolicy","value":"Ignore"}]'
```

## 網路與對外暴露現況（2026-10-02 盤點）

- 兩個 worker：`10.0.158.183`（gateway、postgres、redis）、`10.0.159.167`（backend、consumer、frontend、rabbitmq、keycloak、ingress-nginx）。
- 公開 ingress（同一 host `tymultiverse.cc`，HTTP 會 308 轉 HTTPS）：`/tymb`→backend（**直接公開，不經 gateway**，前端直接呼叫）、
  `/tymg`→gateway、`/`→前端、`/sso`、`/jenkins`（Keycloak SSO + 2FA）、`/maya-sawa` 等。consumer 只有 ClusterIP。
  舊網域 `peoplesystem.tatdvsonorth.com` 的頁面 301 到新網域；`/sso` `/jenkins` `/tymb` `/tymg` `/maya-sawa` `/images` 在舊網域仍照常服務以相容舊 API 呼叫者（見 `tymultiverse-domain/README.md`）。
- **CNI 只有 flannel，NetworkPolicy 不會被執行**：既有的 `default/postgres` policy 從未生效，叢集內 pod 之間沒有隔離。
  要做網段隔離需先裝 Calico（policy-only 模式）或改用支援 policy 的 CNI——這是獨立的基礎設施決策，
  在那之前不要新增 NetworkPolicy（不會生效，只會造成「有保護」的錯覺）。
- 尚未處理：ingress 層的 rate limiting、`/jenkins` 來源 IP 白名單。

## Ingress 範本：Jenkins

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: jenkins-ingress
  namespace: default
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-http01
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - tymultiverse.cc
      secretName: tymultiverse-cc-tls
  rules:
    - host: tymultiverse.cc
      http:
        paths:
          - path: /jenkins
            pathType: Prefix
            backend:
              service:
                name: jenkins-service
                port:
                  number: 8080
```

## Jenkins SSO + Google Authenticator 2FA（接 Keycloak / oic-auth）

讓 Jenkins 登入改走 Keycloak（PeopleSystem realm），強制 Google Authenticator（TOTP）二階段驗證。**不需要 miniOrange 付費 plugin**，用開源 `oic-auth` 即可。

### 前提

- Keycloak 已啟用 TOTP（`CONFIGURE_TOTP`，realm `PeopleSystem` 與 `master` 皆 `defaultAction=true`）
- 既有使用者要強制 2FA 須**逐一**加 required action（Keycloak 的 default action 只套用新建使用者）：
  ```bash
  kubectl exec <keycloak-pod> -- /opt/keycloak/bin/kcadm.sh update users/<USER_ID> -r PeopleSystem \
    -s 'requiredActions=["CONFIGURE_TOTP"]'
  ```
- ⚠️ **不要把同一個 admin/admin 帳號（kcadm 自動化用）也強制 TOTP**。direct grant 會因「帳號有未完成 required action」回 `invalid_grant`。

### Keycloak 端（client）

PeopleSystem realm 建一個 OpenID Connect client：
- Client ID：`jenkins`
- Client authentication：**On**（confidential，client_secret_basic）
- Valid redirect URIs：`https://tymultiverse.cc/jenkins/securityRealm/finishLogin`
- Valid post logout redirect URIs：`https://tymultiverse.cc/jenkins/*`
- Web origins：`https://tymultiverse.cc`
- Credentials 分頁取得 Client secret

### Jenkins 端

1. 裝 plugin **OpenId Connect Authentication**（id `oic-auth`）。
2. Manage Jenkins → Security → Security Realm 改 **Login with OpenID Connect**：
   - Client id：`jenkins`
   - Client secret：貼上 Keycloak 的 secret
   - Configuration mode：Discovery via well-known endpoint
   - Well-known endpoint：`https://tymultiverse.cc/sso/realms/PeopleSystem/.well-known/openid-configuration`
   - Advanced → User fields：User name field=`preferred_username`、Full name=`name`、Email=`email`
3. Authorization 維持 "Logged-in users can do anything"。
4. Save。新無痕視窗測試 → 跳轉 Keycloak → 密碼 + Google Authenticator → 回 Jenkins。

### 兩個踩過的雷（重要）

1. **`invalid_scope`**：oic-auth discovery 模式預設請求 Keycloak 全部 scope（含 `service_account`、`organization`），Keycloak 直接拒絕。
   解法：config.xml 的 `<serverConfiguration>` 內加：
   ```xml
   <scopesOverride>openid email profile</scopesOverride>
   ```

2. **`unauthorized_client` / `Invalid client credentials`**：client secret 填錯（剪貼簿 `I`/`l`/`0`/`O` 混淆）。
   緊急救援：用 SSH 直接把**明碼** secret 寫進 config.xml，Jenkins 載入會自動加密；之後在 UI 點 Save 持久化：
   ```bash
   kubectl exec <jenkins-pod> -- sh -c \
     "sed -i 's#<clientSecret>.*</clientSecret>#<clientSecret>明碼SECRET</clientSecret>#' /var/jenkins_home/config.xml"
   kubectl delete pod <jenkins-pod>   # 重啟套用
   ```

### 鎖死救援（OIDC 設錯時）

```bash
kubectl exec <jenkins-pod> -- sh -c \
  "sed -i 's#<securityRealm .*#<securityRealm class=\"hudson.security.HudsonPrivateSecurityRealm\">#' /var/jenkins_home/config.xml"
kubectl delete pod <jenkins-pod>   # 重啟，回本地帳號
```

> ⚠️ Keycloak pod 用 `start` 模式，每次重啟會做 build/augment，啟動約需 2–3 分鐘，期間 `/sso` 短暫 502，屬正常；資料都在 Postgres，不會遺失。

## 共享 RWO PVC（Jenkins 與其他服務）

RWO 限制：同一時間只能掛載到同一台節點。

```bash
# 找出 Jenkins 所在節點並打標籤
kubectl -n default get pod -l app=jenkins -o wide
kubectl label node <YOUR_NODE_NAME> shared-pvc=true --overwrite

# 固定 Jenkins 到該節點
kubectl -n default patch deploy jenkins --type merge -p '{
  "spec":{"template":{"spec":{"nodeSelector":{"shared-pvc":"true"}}}}
}'
```

其他服務（如 Redis）使用 `claimName: shared-pvc-1` 並以 `subPath` 區隔，且需加 `nodeSelector: shared-pvc: "true"`。

## 快速上傳角色圖片到 OKE image-server

本地 `~/Pictures/images/characters/` 的第一層 png／mp4 用 `push-people` 一鍵上傳：mp4 先 faststart（`-c copy`，不重新編碼）→ `scp` 到 `oke-node` → `kubectl cp` 進 `default/image-server` pod 的 `/images/people`（**覆蓋同名檔、保留其餘**）→ 依 pod 內實際內容重產 `pair-videos.json` → 清 `/tmp`。

- **不要**用 `rm -rf /images/*` 全清再傳，會刪掉 PVC 內所有變體圖與影片。
- 函式的唯一來源是 `scripts/push-people.ps1` / `scripts/push-people.sh`；腳本更新後已開著的視窗要 `push-people-reload`（先確認印出的版本號是最新）。
- 安裝、為什麼要 faststart 與 manifest、實作細節、疑難排解：見 [docs/PUSH_PEOPLE.md](docs/PUSH_PEOPLE.md)。
- 操作流程也整理成 skill `push-people-oke`（`~/.codex/skills/`，Claude 端為 junction）。
