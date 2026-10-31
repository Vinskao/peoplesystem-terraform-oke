# tymultiverse.cc 接入狀態

2026-10-31：Porkbun 顯示網域註冊至 2029-10-31。根域 A 紀錄已指向 OKE nginx Ingress 公開 IP `140.245.52.231`（原 root ALIAS 為 `pixie.porkbun.com`，TTL 600）；wildcard CNAME 仍指向 `pixie.porkbun.com`。不要變更其他用途而未檢查。

`preview-ingress.yaml` 已套用，將新域名無前綴路徑在伺服器端重寫到現有前端；舊的 `/tymultiverse` 路徑仍可用。獨立憑證 `tymultiverse-cc-tls` 已由 `letsencrypt-http01` 核發。首頁、無前綴 `/about/` 和 `/api/market/dashboard/macro` 回應 200，無效頁面 404，舊域首頁 200。此為過渡設定：Astro 建置及部分站內連結仍帶 `/tymultiverse`，SSO 與完整功能仍待驗證，不能宣稱無前綴遷移完成。

上線前需要：

1. 盤點前端使用目前網域的 API、登入、canonical、靜態資源、郵件、分享及 OAuth 回呼；明確區分先保留舊域與遷移的項目。不要將 Jenkins、Keycloak 管理頁或 Maya 私有 API 透過新域名泛用代理而無授權稽核。
2. 測試登入完整流程及新域名相關 cookie、CORS、CSRF、Keycloak redirect URI、OIDC issuer 與 logout。Keycloak 目前使用固定舊網域，切勿未驗證就修改 issuer 或刪除舊域回呼；既有使用者與服務可能受影響。
3. 確認只公開預期路徑並保護敏感 API，再設計根網址與 `/tymultiverse/` 的 canonical/redirect、robots、sitemap、SEO 及 AdSense 驗證。資料流與安全政策需先有未登入的實際測試。
4. 確認新域及 www 是否都需要後，準備相應 DNS 與憑證；原本 root ALIAS 必須先安全替換，避免衝突，先記錄舊值和 TTL。既有寄信地址使用舊網域，不應隨意變更 MX、SPF、DKIM、DMARC。
5. 預備回復程序，檢查舊站、SSO、API、使用者資料、社群排程，驗證 HTTPS、證書續期與授權邊界，然後才考慮對外切換或登記 AdSense。

本次變更僅限新域名的 Porkbun 根域 DNS 與新增 Ingress；Gateway、Keycloak 和既有域名設定未更動。TLS 自動續期需要持續確認 ACME HTTP-01 在 root 重寫設定下仍可正常路由，不得使用全站 permanent-redirect annotation（曾攔截 ACME challenge）。

## 2026-10-31 遷移稽核

- 使用者已在多個本地儲存庫進行未提交的網域文字替換；這些內容不得覆寫或直接整批部署。前端 `astro.config.ts` 的 `base` 仍為 `/tymultiverse`，而 `Nav.astro`、`NavScript.ts` 與其他程式仍有大量硬編碼前綴，Ingress 重寫並不會讓輸出的連結自動去除前綴。
- Gateway 的 `KeycloakController` 使用 `url.frontend` / `PUBLIC_FRONTEND_URL` 決定登入成功後的目標；client scope `birch.publish` 並非該登入回跳位置。需同時核對 Keycloak 客戶端 redirect URI、Gateway 實際值和 cookie 權限，再完整測試授權、回跳、登出。
- 使用者工作目錄中部分 `k8s/deployment.yaml` 已將原域名改為新域名卻仍使用舊 `peoplesystem-tls` Secret；不能套用這些變更取代現有 Ingress，否則可能移除舊域路由並使用不符合新域的憑證。維持獨立新域 Ingress 和 `tymultiverse-cc-tls`，逐一核對 Maya、Gateway、backend 安全邊界後再決定哪些路徑可以接入。
- Jenkins 從 Git checkout，單純重新觸發不會納入未提交修改；必須先審核、測試、依各專案正確切分並提交變更，確認實際 build commit 和部署 image，再驗證上線狀態。
- OKE 目前 Keycloak Deployment 的 `KC_HOSTNAME` 為 `peoplesystem.tatdvsonorth.com`，`KC_HTTP_RELATIVE_PATH` 是 `/sso`；Gateway 的 `PUBLIC_FRONTEND_URL` 與 `KEYCLOAK_AUTH_SERVER_URL` 是由 Kubernetes Secret 注入。不要把 Secret 內容列入日誌或文件。只更改本機部署 YAML 不會自動更新這些線上配置或 Keycloak 客戶端 URI。
- 2026-10-31 前端針對 home、SEO、API 與 contact 的局部測試結果為 53 通過、1 失敗：`tests/api/publicSpec.test.ts` 對 API 文案作舊字串斷言，與目前頁面不一致。需要核對實際授權能力並修正語意及測試；不可為了通過而保證未經驗證的私有資料存取保護。
- 郵件移轉準備：Porkbun 已新增 `mx.tymultiverse.cc` A → `140.245.52.231`，TTL 600；`tymultiverse-domain/mail-certificate.yaml` 建立新的獨立 `mail-system/tymultiverse-mail-public` 憑證，已顯示 Ready，不取代舊信箱所使用的 `mail-public`。新網域 MX、OCI approved sender、DKIM、SPF、轉寄與 Thunderbird 設定尚未完成。線上 Postfix 目前仍服務 `peoplesystem.tatdvsonorth.com`，使用者批次替換後的郵件文件與本機設定不代表它已生效。Thunderbird 視窗存取工具未能選取該視窗；不得假稱已修改客戶端。新舊地址應並行直到兩者收發完整測試通過。

## 2026-10-31 新網域收信已上線

`tianyikao@tymultiverse.cc` 與舊地址並行收信，舊網域設定未變。

- OCI（`ty-mail` 區室）：Email Domain `tymultiverse.cc`、DKIM selector `tymc20261031`（DNS 與簽章皆 Active）、Approved Sender `tianyikao@tymultiverse.cc`。Policy `ty-mail-relay-send` 條件改為 `any {email-domain = 'peoplesystem.tatdvsonorth.com', email-domain = 'tymultiverse.cc'}`；描述欄仍寫舊網域。
- Porkbun DNS（TTL 600）：MX `tymultiverse.cc` → 10 `mx.tymultiverse.cc`；TXT `v=spf1 include:ap.rp.oracleemaildelivery.com -all`；CNAME `tymc20261031._domainkey` → `tymc20261031.tymultiverse.cc.dkim.xsp1.oracleemaildelivery.com`。未設 DMARC。
- Postfix：`virtual_alias_domains` 加入新網域，三個地址（tianyikao／postmaster／abuse）轉 Gmail；`mail-public` 憑證同時涵蓋兩個 mx 名稱。另一張 `tymultiverse-mail-public` 憑證未掛載使用，可刪除。
- 轉寄程式的寄件者仍是 `tianyikao@peoplesystem.tatdvsonorth.com`（`mail/relay/forward.py` 的 `SENDER`），ARC 只簽舊網域。要改寄件者時，先確認新 Approved Sender 可用，再改程式與 `test_oci_forward.py`。
- 驗證：`verify_smtp.py` 新增 3 項（新地址 250、未知地址 550、憑證 SAN），部署前紅、部署後 11/11 綠；`verify_oci_config.py` 5/5、`verify_proxy_smtp.py` 4/4。外部探測 TLS1.3、250／550／554。Gmail → 新地址 → Gmail 往返主旨 `TY tymultiverse.cc roundtrip 20261031-1`，佇列 `09FEB2442551`，已進 Gmail。
- Thunderbird 未設定；這套系統沒有 IMAP 信箱，收信仍在 Gmail。

## 下次遷移的操作順序

1. 先逐一檢查前端、Gateway、backend、maya-sawa、consumer、common 和基礎設施的 `git status -sb`、`git diff` 與線上部署版本；工作目錄有使用者修改，禁止 reset、覆蓋或直接全量提交。列出新舊網域、`/tymultiverse` 在程式碼、CI、Kubernetes、Keycloak、DNS、排程、公開文件及郵件中的用途。保留需要相容的舊連結、寄信網域與歷史資料來源，不能機械式全域取代。
2. 定義前端在 `https://tymultiverse.cc/` 的根路徑部署，清除所有對外導覽、內部連結、語系切換、API、資源、回跳及 canonical 的 `/tymultiverse` 前綴；舊網址提供測試過的相容方式。以實際請求驗證首頁、子頁、圖表、API、靜態資源及不存在的路徑，禁止用所有路徑回首頁掩蓋 404。前端 bug 與新增邏輯依工作區 AGENTS.md 先寫失敗測試，再修正並執行相關測試及 build。
3. 先檢查 Gateway 設定來源：`src/main/resources/application.yml` 的 `url.frontend` 對應 `PUBLIC_FRONTEND_URL`，`KeycloakController` 用它產生登入完成的導向。確認 Keycloak **client** 的精確允許回跳、登出 URI、web origins，再釐清 Gateway callback、登入狀態與瀏覽器 cookie 的網域；`birch.publish` client scope 不是登入回跳設定。保留原 issuer 與既有客戶端，直到所有依賴已驗證。測試未登入、登入、重新整理、登出，以及新舊域上已登入／未登入的流程；不得把 JWT、refresh token 或密碼寫入網址、日誌或文件。
4. 新增各服務對外路由前，逐一確認是否需要公開及後端授權是否有效；不要因接新域而直接曝露 Keycloak 管理介面、Jenkins、個人帳務或 Maya 管理 API。驗證匿名／一般使用者對私有 API 的拒絕，以及使用者可使用的既有公開研究功能。
5. 釐清新域 canonical、sitemap、robots、社群發文、AdSense、聯絡信箱與來源連結；正式可抓取內容與新域狀態先驗證後才提交 Google 審查。舊域的 email、SSO、其他專案與使用者資料仍可能依賴 `peoplesystem.tatdvsonorth.com`，遷移不等於刪除舊域。
6. 對確實需要的各專案分別執行其規定的測試與 build，人工檢查差異，再將授權且經審核的變更提交對應分支；Jenkins 執行後核對其 checkout commit、build 結果、部署 image tag、rollout 與線上功能。只重建／部署受影響服務，不要為了改前端網址而無差別重啟 Keycloak 或資料庫。

## 快速檢查與回復

- 先用 `ssh oke-node 'kubectl get ingress -n default'` 檢查線上主機與 IP，並用 `ssh oke-node 'kubectl get certificate tymultiverse-cc-tls -n default'` 檢查憑證 Ready；不要輸出 Secret、憑證私鑰或登入資料。
- 使用瀏覽器測試 `https://tymultiverse.cc/`、無前綴子頁與實際導覽結果；檢查原站與登入，不以 HTTP 200 代替登入、授權或內容正確性的驗證。檢查 ACME solver 路徑在 HTTP／HTTPS 中沒有被根路由錯誤重寫。
- 若新域 Ingress 造成問題，可在確認影響後僅刪除 `tymultiverse-domain-root` 與 `tymultiverse-domain-frontend`，或重新套用已審核的前版 `preview-ingress.yaml`；不要刪除 `peoplesystem-tls`、舊域 Ingress 或 Keycloak 資料。DNS 要回復時，原根域為 `ALIAS pixie.porkbun.com`、TTL 600；先確認後續是否已有新紀錄或郵件設定，再修改。DNS／憑證回復均需重新驗證。
- 時間敏感資訊（IP、網域到期、DNS、部署映像、憑證狀態與工作目錄差異）是調查時的快照，執行前重新查證。

## 2026-10-31 網站移到 https://tymultiverse.cc/ 根路徑

- 前端 `base` 改為 `/`（ty-multiverse-frontend `9adec64`、`2625109`）。舊網址（舊網域任何頁面、任一網域的 `/tymultiverse/...`）由前端 middleware `src/scripts/site/legacyRedirect.ts` 回 301 到新網域同一頁並保留 query。ingress-nginx 的 `permanent-redirect` 不接受 `$2` 等變數（admission webhook 拒絕），所以轉址放在應用程式裡。
- 前端 Jenkinsfile 只做 `kubectl set image`，**不會套用 `k8s/deployment.yaml` 的 Ingress**。改前端 Ingress 後要手動 `kubectl apply`。
- 新網域路由：`ty-multiverse-frontend-ingress`（`/` → 前端）；其他服務見 `mirror-ingress.yaml`。`tymcc-portfolio-api-protected` 把 `/api/market/portfolio` 送到 maya-sawa（需登入，未登入 401），前端部署時必須保留。
- 舊網域：`ty-multiverse-frontend-legacy-ingress`（`/tymultiverse` 與 `/` Prefix → 前端轉址）；`/sso`、`/jenkins`、`/tymb`、`/tymg`、`/maya-sawa`、`/images` 仍照常服務，等 Keycloak 換網域後再處理。
- 憑證 `tymultiverse-cc-tls` 改由 `certificate.yaml` 獨立管理（已移除對舊 Ingress 的 ownerReference）。`preview-ingress.yaml` 的兩個過渡規則已刪除。
- Jenkins `vinskao` 資料夾的 `PUBLIC_TYMB_URL`、`PUBLIC_TYMG_URL`、`PUBLIC_PEOPLE_IMAGE_URL`、`PUBLIC_API_BASE_URL`、`PUBLIC_DECKOFCARDS_URL`、`PUBLIC_MAYA_SAWA_URL` 改為新網域，`PUBLIC_FRONTEND_URL` 改為 `https://tymultiverse.cc/`。`PUBLIC_SSO_URL`、`KEYCLOAK_AUTH_SERVER_URL` 仍是舊網域。線上 gateway secret 的 `PUBLIC_FRONTEND_URL` 尚未更新，下次 gateway 部署才會生效；在那之前登入回到舊網址，再經 301 帶 query 回新網域。
- Keycloak PeopleSystem realm 的 `peoplesystem` client 加入 redirect URI `https://tymultiverse.cc/*` 與 web origin `https://tymultiverse.cc`，舊網域設定保留。
- 驗收：`python tymultiverse-domain/verify_routes.py`。
