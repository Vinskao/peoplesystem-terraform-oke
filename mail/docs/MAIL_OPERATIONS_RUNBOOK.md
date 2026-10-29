# 自有網域郵件操作手冊

更新：2026-10-29。主信箱 `tianyikao@peoplesystem.tatdvsonorth.com`，目的信箱 `tianyikao@gmail.com`。

## 架構與邊界

```text
外部寄件 MTA → MX → 現有 OCI LB TCP25（PROXY v1）
  → worker NodePort31225 → Postfix2525 → 持久佇列
  → nobody 執行的轉寄程式 → OCI SMTP465 TLS → Gmail
```

一般 port25 留給內部 SMTP 與健康測試；公開流量走要求 PROXY header 的2525。Postfix終止 STARTTLS，使用 cert-manager 簽發的 Let's Encrypt 憑證。既有 ingress-nginx 的80、443與PostgreSQL5432不變。

OCI backend set/listener：`TY-MAIL-25`，backend為 `10.0.158.183:31225`，TCP健康檢查同埠；listener為TCP25、idle300秒、PROXYv1、無隱含SSL終止。LB公網IP為140.245.52.231。實際LB OCID需由Console核對；舊Service annotation有過期OCID，不能直接當作正確資源。

## DNS

以下名稱位於 Hostinger 的 `tatdvsonorth.com` zone，TTL300。

| 類型 | 相對名稱 | 值 |
| --- | --- | --- |
| A | mx.peoplesystem | 140.245.52.231 |
| MX | peoplesystem | 優先序10，mx.peoplesystem.tatdvsonorth.com |
| TXT | peoplesystem | v=spf1 include:ap.rp.oracleemaildelivery.com -all |
| CNAME | oci20261029._domainkey.peoplesystem | oci20261029.peoplesystem.tatdvsonorth.com.dkim.xsp1.oracleemaildelivery.com |

`smtp-out.peoplesystem` A指向140.245.44.81，是先前直接外寄／PTR路線的紀錄，不是目前MX，也不是OCI寄信endpoint。根網域的Hostinger MX／SPF保留。

網路規則：LB安全清單允許0.0.0.0/0到TCP25；LB出站只新增10.0.158.183/32 TCP31225；worker NSG入站只新增10.0.128.0/27 TCP31225。不要為此開放所有worker埠或改動其他listener。

## OCI 身分與秘密

- Compartment：`ty-mail`；Email Domain：`peoplesystem.tatdvsonorth.com`。
- 專用user/group：`ty-mail-relay`，只有SMTP credentials能力，無Console本機密碼、API key或Auth token能力。
- Policy：只在ty-mail允許`use approved-senders`，並以`target.approved-sender.email-domain`限制本網域。
- Approved sender只有實際使用的`tianyikao@peoplesystem.tatdvsonorth.com`，必須與上述區室一致。
- Secret：`mail-system/oci-smtp`，key為`relay.json`。`store_smtp_secret.py`只從stdin取得資料，以kubectl create寫入，避免apply註解保存明文；不同既存Secret不覆寫。
- init container將執行期憑證複製到node-local state的私有路徑，owner65534、目錄0500／檔案0400。節點管理員仍可讀取，這不是對root隔離。
- 本次傳輸使用一次性RSA-OAEP加密檔，伺服器直接解密到匯入程式stdin；暫存私鑰與密文已刪除。密碼不放文件、Git、截圖或命令參數。

## 轉寄語意與限制

OCI要求核准的header From與envelope From，不能透明冒用任意外部寄件者。轉寄程式以自有地址寄出，保留原始寄件者／有效Reply-To，提供純文字預覽與完整`original.eml`附件。HTML腳本不執行，驗證連結保留。

收件目的地固定為擁有者Gmail；未知地址在SMTP RCPT階段拒絕，無catch-all，也不信任整個叢集網段作轉寄。外寄失敗回傳EX_TEMPFAIL75，保留Postfix佇列重試；沒有直接TCP25fallback。

目前原信上限1,000,000 bytes，預留包裝與base64附件空間，送OCI前另檢查2,000,000 bytes上限。這不是一般10MB／25MB信箱。接受更大郵件前必須一起調整OCI quota、Postfix及程式兩個大小限制。

佇列在`/var/lib/ty-mail`的node-local hostPath，能承受pod重建，不能承諾節點遺失時不丟信。備份、復原演練與自動憑證更新後的Postfixreload／restart仍需持續維護。

## 部署與驗證

```sh
kubectl apply --dry-run=server -k mail/production
kubectl apply -k mail/production
kubectl -n mail-system rollout status statefulset/ty-mail --timeout=300s
kubectl -n mail-system get certificate mail-public
kubectl -n mail-system exec ty-mail-0 -- postqueue -p
python -B -m unittest discover -s mail/tests -p test_oci_forward.py -v
python -B -m unittest discover -s mail/tests -p test_store_smtp_secret.py -v
```

pod內執行`verify_smtp.py`九項、`verify_oci_config.py`五項、`verify_proxy_smtp.py`四項；設定parser測試可用RELAY_CONFIG_DIR檢查候選目錄。外部探測需驗證系統CA／hostname、正確地址250、未知地址550、外部relay554，不能只看TCP可連。

2026-10-29已確認Gmail收到OCI轉寄測試信，顯示本網域DKIM、TLS與original.eml；公開SMTP也通過TLS1.3及收件限制檢查。MX已公開解析。完整Gmail往返信主旨為`TY public mail roundtrip 20261029-1137`，Postfix佇列ID為`39E57243B882`，Google來源IP為209.85.161.52；已確認轉寄信回到Gmail Inbox，而非只排入佇列。

## 用自訂地址寄信

**時效限制（2026-10-29查證）：Google官方公告2027年1月起停止第三方地址Send-as；Google Workspace alias與其他Gmail地址不受此項公告影響。因此Gmail外部SMTP設定只適合目前過渡使用，長期應選支援獨立SMTP身分的客戶端，或另行規劃Workspace網域信箱。**

可以在Gmail「設定→查看所有設定→帳戶和匯入→以其他地址寄信→新增其他電子郵件地址」設定此地址，並選擇透過OCI SMTP寄送。Gmail會寄確認信到該地址，經本系統轉回Gmail後完成驗證。

SMTP server：`smtp.email.ap-singapore-2.oci.oraclecloud.com`；587搭配STARTTLS，或465搭配SSL/TLS；帳號與密碼是OCI產生的SMTP credentials，帳號不是email地址，也不是Google密碼。From與envelope From須符合Approved Sender。

建議為Gmail／個人郵件軟體另建可獨立撤銷的SMTP憑證，限制同一核准地址，勿共用自動轉寄憑證。目前只完成伺服器憑證，尚未替Gmail建立或保存寄件憑證。此手冊不代表Gmail已能以該地址寄出。

Thunderbird、Apple Mail等可設定獨立SMTP identity，但收件仍用Gmail帳戶；這套系統沒有新增IMAP／POP信箱。部分軟體的簡化帳戶設定不接受這種收寄分離，需要進階設定。Gmail的Send-as不保證自動同步成其他軟體的寄件身分。

官方：[Gmail Send as](https://support.google.com/mail/answer/22370?hl=en)、[OCI SMTP設定](https://docs.oracle.com/en-us/iaas/Content/Email/Reference/gettingstarted_topic-Configure_the_SMTP_connection.htm)。
