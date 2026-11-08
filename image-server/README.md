# image-server（/images/people/）

`nginx.conf` 是正式環境 ConfigMap `nginx-config`（key `nginx.conf`）的內容，以 subPath 掛進 `deploy/image-server`。subPath 掛載不會自動更新，改完要重啟 pod。

套用方式（先驗證再套用）：

```bash
scp image-server/nginx.conf oke-node:/tmp/nginx.conf.new
ssh oke-node "kubectl exec -i deploy/image-server -n default -- sh -c 'cat > /tmp/n.conf && nginx -t -c /tmp/n.conf' < /tmp/nginx.conf.new"
ssh oke-node "kubectl get configmap nginx-config -n default -o yaml > /tmp/nginx-config.backup.yaml; kubectl create configmap nginx-config -n default --from-file=nginx.conf=/tmp/nginx.conf.new --dry-run=client -o yaml | kubectl apply -f - && kubectl rollout restart deploy/image-server -n default"
curl -sI https://tymultiverse.cc/images/people/walking.mp4   # content-type: video/mp4, 只有一個 cache-control
```

快取策略：`public, max-age=86400, must-revalidate`（1 天後用 ETag/Last-Modified 重新驗證）。檔案常以同名覆蓋（例如 `walking.mp4`），所以不用長快取；要立刻換新請改檔名或在網址加 `?v=`。

注意：圖片儲存 `image-pv` 是綁在節點 `10.0.159.167` 的本機卷（nodeAffinity），image-server 只能跑在那台。那台被 cordon 時重啟 image-server 會卡在 Pending，所有人物圖片與影片會中斷。
