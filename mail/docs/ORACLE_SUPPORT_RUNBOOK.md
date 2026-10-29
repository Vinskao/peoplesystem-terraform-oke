# OCI 郵件支援案件操作手冊

更新：2026-10-29。這是本次帳戶的實際處理紀錄，不代表所有帳戶均能取得相同核准。

## 入口與分工

| 問題 | 官方入口 | 提交重點 |
| --- | --- | --- |
| 區域外寄 TCP 25 限制 | https://cloud.oracle.com/support/limit-increases/create-request?region=ap-singapore-2 | 區域、tenancy OCID、用途、預估量 |
| PTR／反向 DNS | OCI 技術服務請求 | 公網出口 IP、要求的主機名稱、已生效的正向 A |
| 找不到表單限制項目 | Console Help → Request help → Ask Oracle → Live agent | 提供既有 SR，請確認應轉交團隊 |
| 本次既有案件 | https://cloud.oracle.com/support/tech/4-0004161116/comments?region=ap-singapore-2 | 集中更新證據，避免拆成互不相連的案件 |

本次主要區域為 Singapore West，API region 為 `ap-singapore-2`。使用者確認帳戶為 Pay As You Go；Identity Domain 的 Free 類型不是帳戶計費方案證據。

## 本次有效的處理方法

1. 先從 SR 留言讀出缺少的資料：tenancy OCID、每月預估寄送量，以及 PTR 所需的 forward DNS。
2. 依實際需求回覆每月約 100 封，說明自有網域收信與轉寄用途；識別資料只放官方案件，不放公開文章。
3. 在 Hostinger 的 `tatdvsonorth.com` zone 新增 `smtp-out.peoplesystem` A。只填 `smtp-out` 會建立另一個不同的名稱。
4. 從公用 DNS 查到 `smtp-out.peoplesystem.tatdvsonorth.com → 140.245.44.81`，才回覆「DNS 已就緒」。不能以 DNS 控制台有一列紀錄代替公開解析證據。
5. Service Limits 表單的 VCN 選項只有一般配額，沒有可對應 TCP 25 的選項。沒有提交不相干的配額，改向既有 SR 與真人支援要求釐清路由。
6. 2026-10-28 真人客服 Sergiu 表示 TCP 25 解封由 CAM（Customer Account Management）處理，沒有 CAM 即時聊天入口；應請現有 SR 團隊轉交。已將轉交要求與 PAYG 狀態寫回 SR。
7. Sergiu 表示 port 25 unblock 本身不收費。這是本次支援回覆，不等於 VM、流量、公網 IP 或郵件服務都免費。

Oracle 同日在案件確認 PTR 所需資料完整，可進行驗證；這不是 PTR 已建立或 TCP 25 已解除的證據。未找到 Service Limits 項目時，官方同意留在原 SR 做路由檢查，沒有用錯誤配額硬送。

## 可重用的回覆內容

```text
Region: ap-singapore-2
Tenancy OCID: <copy the actual tenancy OCID privately>
Account: Pay As You Go (owner confirmed)
Projected volume: approximately 100 emails/month
Use case: receive mail for our own domain and forward to the owner's inbox.
The Service Limits form does not expose a TCP/25-specific item.
Please route this existing SR to CAM for regional SMTP exemption review.
Forward DNS: <hostname> resolves publicly to <actual egress IP>.
Please validate the forward record before creating the requested PTR.
```

要附查詢時間、來源與結果；不要提供密碼、SMTP token 或不相關客戶郵件。若入口要求首次接受具法律效力的條款，交由帳戶擁有者確認；本次未接受 My Oracle Support 首次使用條款。

## 架構決策與目前狀態

最後選擇 OCI Email Delivery 作外寄 relay，使用 TLS 465，故收信系統不依賴外寄 TCP 25 解封，也不依賴自有出口 PTR。公開 TCP 25 是「外部郵件送進來」的入口，與 OCI 封鎖「向外連線的 TCP 25」不同。

不要把「已改用 managed relay」寫成「原豁免申請成功」。原 SR 曾要求 CAM 轉交，尚未取得解封完成證據。待完整收信驗證後，再回覆案件新架構與是否仍需處理；不假設案件自動取消。

## 官方參考

- [OCI 外寄 SMTP 限制](https://docs.oracle.com/en-us/iaas/releasenotes/changes/f7e95770-9844-43db-916c-6ccbaf2cfe24/index.htm)
- [OCI Reverse DNS](https://docs.oracle.com/en-us/iaas/Content/DNS/Tasks/reversedns.htm)
- [OCI Email Delivery](https://docs.oracle.com/en-us/iaas/Content/Email/home.htm)
- MOS KB94353：OCI Networking — TCP port 25 limit request is granted on a regional basis（可能需登入）。
