# TY Multiverse Root Agent Notes

## Jenkins Access

- Jenkins base URL:
  - `https://peoplesystem.tatdvsonorth.com/jenkins/`
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
        - peoplesystem.tatdvsonorth.com
      secretName: peoplesystem-tls
  rules:
    - host: peoplesystem.tatdvsonorth.com
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
- Valid redirect URIs：`https://peoplesystem.tatdvsonorth.com/jenkins/securityRealm/finishLogin`
- Valid post logout redirect URIs：`https://peoplesystem.tatdvsonorth.com/jenkins/*`
- Web origins：`https://peoplesystem.tatdvsonorth.com`
- Credentials 分頁取得 Client secret

### Jenkins 端

1. 裝 plugin **OpenId Connect Authentication**（id `oic-auth`）。
2. Manage Jenkins → Security → Security Realm 改 **Login with OpenID Connect**：
   - Client id：`jenkins`
   - Client secret：貼上 Keycloak 的 secret
   - Configuration mode：Discovery via well-known endpoint
   - Well-known endpoint：`https://peoplesystem.tatdvsonorth.com/sso/realms/PeopleSystem/.well-known/openid-configuration`
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

## 快速上傳角色圖片到 OKE 內部 Postgres

本地開發時，常需把 `~/Pictures/images/characters/` 的圖片更新到叢集內供圖的位置。一個縮短指令 `push-people` 可一鍵完成完整流程。

**供圖架構**：圖片由 `default/image-server`（nginx）pod 提供，掛 PVC `image-pvc` 到 `/images/people`，pod 跑在 node `10.0.159.167`。前端從 `https://peoplesystem.tatdvsonorth.com/images/people/<name>.png` 取圖。

**`push-people` 做的事（完整三步）**：
1. `scp` 本機第一層 png/mp4 → `oke-node:/tmp/`
2. `ssh oke-node` → `kubectl cp /tmp/*` 進 `image-server` pod 的 `/images/people/`（**覆蓋同名檔、保留其餘**，非破壞性）
3. `rm -f /tmp/*.png /tmp/*.mp4` 清乾淨 `/tmp`

> **不要用 `rm -rf /images/*` 全清再上傳**（舊 Mac 腳本的做法）——那會刪掉 PVC 內所有圖（含 Fighting/Dancing 變體與影片）。除非你本機真的有「全套」檔案要完整取代，否則用覆蓋模式。
>
> 上傳後前端可能因瀏覽器/CDN 快取看不到新圖，需 hard refresh（Ctrl+Shift+R）。

### 前提

- `~/.ssh/config` 已定義 `oke-bastion` 與 `oke-node`（含 ProxyJump）：
  ```
  Host oke-bastion
    HostName 140.245.61.250
    User opc
    IdentityFile ~/.ssh/id_ed25519
  
  Host oke-node
    HostName 10.0.0.69
    User opc
    IdentityFile ~/.ssh/id_ed25519
    ProxyJump oke-bastion
  ```
- Git Bash 已載入 `~/.bashrc`（含 `push-people` 函式）

> **注意**：函式定義是 shell 專屬的。Bash 函式（`~/.bashrc`）在 PowerShell 跑不動，反之亦然。
> 若你 Windows 上同時用 PowerShell 和 Git Bash，**兩邊都要各設一份**（見下）。

### 設置（Git Bash / Zsh / Linux）

加入 `~/.bashrc`（Git Bash）或 `~/.bash_profile` + `~/.bashrc`（Zsh/Linux）：

```bash
# 一鍵：上傳 png/mp4 → 搬進 image-server pod（覆蓋、保留其餘）→ 清 /tmp
# 用法（任何路徑都可）： push-people
# 需要 ~/.ssh/config 內已定義 oke-node（含 ProxyJump oke-bastion）
push-people() {
  local src="$HOME/Pictures/images/characters"
  (
    shopt -s nullglob
    cd "$src" || { echo "找不到資料夾: $src"; return 1; }
    local files=( *.png *.mp4 )
    if (( ${#files[@]} == 0 )); then
      echo "$src 裡沒有 png/mp4 可上傳"
      return 1
    fi
    echo "[1/2] 上傳 ${#files[@]} 個檔案到 oke-node:/tmp/ ..."
    scp "${files[@]}" oke-node:/tmp/ || { echo "scp 失敗"; return 1; }
    echo "[2/2] 搬進 image-server pod（覆蓋、保留其餘）並清 /tmp ..."
    ssh oke-node '
POD=$(kubectl get pod -l app=image-server -o jsonpath="{.items[0].metadata.name}")
n=0
for f in /tmp/*.png /tmp/*.mp4; do
  [ -f "$f" ] || continue
  kubectl cp "$f" "$POD:/images/people/$(basename "$f")" >/dev/null 2>&1 && n=$((n+1))
done
echo "migrated $n files into $POD"
rm -f /tmp/*.png /tmp/*.mp4
echo "cleaned /tmp"
'
    echo "完成，硬重整頁面（Ctrl+Shift+R）即可看到新圖"
  )
}
```

Git Bash 若無 `~/.bash_profile`，需建立並 `. ~/.bashrc` 以便登入 shell 載入。

### 設置（Windows PowerShell 5.1）

加入 PowerShell profile（路徑：`$PROFILE`，通常是
`C:\Users\<USER>\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1`）：

```powershell
function push-people {
  $src = "$HOME\Pictures\images\characters"
  if (-not (Test-Path $src)) {
    Write-Host "[x] Directory not found: $src" -ForegroundColor Red
    return
  }
  # 第一層 png/mp4（非遞迴）
  $files = @(Get-ChildItem -Path $src -File | Where-Object { $_.Extension -eq '.png' -or $_.Extension -eq '.mp4' })
  if ($files.Count -eq 0) {
    Write-Host "[x] No png/mp4 files in $src" -ForegroundColor Red
    return
  }
  # 1) 單次 scp 一連線傳全部到 /tmp
  Write-Host "[1/2] Uploading $($files.Count) files to oke-node:/tmp/ ..." -ForegroundColor Cyan
  $paths = $files | ForEach-Object { $_.FullName }
  & scp $paths "oke-node:/tmp/"
  if ($LASTEXITCODE -ne 0) {
    Write-Host "[x] scp failed (code $LASTEXITCODE)" -ForegroundColor Red
    return
  }

  # 2) 搬進 image-server pod（覆蓋、保留其餘）並清 /tmp
  Write-Host "[2/2] Migrating into image-server pod and cleaning /tmp ..." -ForegroundColor Cyan
  # 用單引號 here-string，避免 PowerShell 展開 $(...) 與 $f（讓遠端 shell 處理）
  $remote = @'
POD=$(kubectl get pod -l app=image-server -o jsonpath="{.items[0].metadata.name}")
n=0
for f in /tmp/*.png /tmp/*.mp4; do
  [ -f "$f" ] || continue
  kubectl cp "$f" "$POD:/images/people/$(basename "$f")" >/dev/null 2>&1 && n=$((n+1))
done
echo "migrated $n files into $POD"
rm -f /tmp/*.png /tmp/*.mp4
echo "cleaned /tmp"
'@
  & ssh oke-node $remote
  if ($LASTEXITCODE -eq 0) {
    Write-Host "[ok] Done. Hard-refresh (Ctrl+Shift+R) to see new images." -ForegroundColor Green
  } else {
    Write-Host "[!] remote step exited with code $LASTEXITCODE" -ForegroundColor Yellow
  }
}
```

> **效能雷**：不要用 `foreach` 逐檔呼叫 scp——那會為每個檔案開一次 SSH 連線（70 檔=70 次跳板握手，極慢且畫面像卡住）。改用**一次 scp 傳整個檔案陣列**（PowerShell 會把陣列展開成多個參數），只握手一次。Bash 版的 `scp "${files[@]}" ...` 本來就是單連線。

改完在現有視窗執行 `. $PROFILE` 重新載入，或重開 PowerShell。

#### PowerShell 5.1 踩過的雷（重要）

1. **編碼**：Windows PowerShell 5.1 會把「無 BOM 的 UTF-8」當 ANSI 讀，
   emoji（❌⬆️✅）和中文會變亂碼 → 字串沒收尾 → 整個函式解析失敗。
   → profile 內**只用 ASCII**（訊息別放 emoji/中文），或存成 UTF-8 with BOM。
2. **`-MaxDepth` 不存在**：是 PowerShell 6+ 才有；5.1 的 `Get-ChildItem` 沒這參數。
3. **`-Include` 沒配 `-Recurse` 抓不到東西**。
   → 改用 `Get-ChildItem -File | Where-Object { $_.Extension -eq '.png' ... }`。

### 用法

任何路徑（PowerShell 或 Git Bash）直接執行：
```
push-people
```

會把 `~/Pictures/images/characters/` 內的**第一層** `*.png` 和 `*.mp4`（不含子資料夾如 `characters_padded/`）上傳到 `oke-node:/tmp/`。

之後在 OKE node 上可用 `kubectl cp` / Pod 掛載 `/tmp` 等方式遷移到 `/images/people`。

### 實作細節

- 只抓第一層 png/mp4，自動忽略子資料夾；scp 無 `-r`，不會誤傳遞迴目錄
- Bash 版用 subshell + `cd`，不改變當前路徑
- 依賴 `~/.ssh/config` 的 `oke-node` 定義，自動走 `ProxyJump oke-bastion` 跳板
