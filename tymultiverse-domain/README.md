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
