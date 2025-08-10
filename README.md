# Terraform OKE for Oracle Cloud Infrastructure

[![Documentation](https://github.com/oracle-terraform-modules/terraform-oci-oke/actions/workflows/mdbook.yaml/badge.svg?branch=5.x-mdbook&status=Documentation)](https://oracle-terraform-modules.github.io/terraform-oci-oke/)

## 專案概述

此專案為 Oracle Cloud Infrastructure (OCI) 提供可重複使用的 Terraform 模組，用於部署 [OCI Kubernetes Engine (OKE)](https://docs.cloud.oracle.com/iaas/Content/ContEng/Concepts/contengoverview.htm) 叢集及相關基礎設施。

## 技術規格分析

### 版本要求
- **Terraform**: >= 1.3.0
- **OCI Provider**: >= 7.6.0
- **Kubernetes**: v1.26.2 (預設)
- **CNI**: flannel (預設) 或 npn
- **處理器架構**: ARM (Ampere Altra)

### 核心組件

#### 1. 網路架構 (Network)
- **VCN**: 預設 CIDR `10.0.0.0/16`
- **子網路**: 
  - bastion, operator, cp (control plane)
  - int_lb, pub_lb (load balancers)
  - workers, pods
- **閘道**: NAT Gateway, Internet Gateway, Service Gateway
- **安全群組**: 針對各組件分別配置

#### 2. 叢集配置 (Cluster)
- **類型**: basic 或 enhanced
- **控制平面**: 可選擇公開/私有
- **Pod CIDR**: `10.244.0.0/16`
- **Service CIDR**: `10.96.0.0/16`
- **負載平衡器**: public, internal, 或 both

#### 3. 工作節點 (Workers)
- **預設規格**: VM.Standard.A1.Flex (1 OCPU, 6GB RAM, 46.6GB 磁碟)
- **節點數量**: 4 個節點 (總計 4 OCPUs, 24GB RAM, 186.4GB 磁碟)
- **處理器架構**: ARM (Ampere Altra)
- **管理模式**: 
  - node-pool (預設)
  - virtual-node-pool
  - instance
  - instance-pool
  - cluster-network
- **映像檔**: Oracle Linux 8 (預設)

#### 4. 身份與存取管理 (IAM)
- **動態群組**: 自動建立所需權限
- **政策**: 叢集、工作節點、操作員存取權限
- **標籤**: 支援自由格式和定義標籤

#### 5. 擴展功能 (Extensions)
- **監控**: Prometheus, Grafana
- **網路**: Cilium, Multus
- **安全**: Gatekeeper
- **自動擴展**: Cluster Autoscaler
- **GitOps**: ArgoCD

## 建置步驟

### 前置準備

1. **安裝必要工具**
```bash
# 安裝 Terraform
# 安裝 OCI CLI
# 安裝 kubectl
```

2. **設定 OCI 認證**
```bash
# 設定 OCI 配置檔案
oci setup config

# 或使用 API 金鑰
export TF_VAR_api_fingerprint="your_fingerprint"
export TF_VAR_api_private_key_path="~/.oci/oci_api_key.pem"
export TF_VAR_tenancy_id="ocid1.tenancy..."
export TF_VAR_compartment_id="ocid1.compartment..."
```

### 快速部署

#### 方法一：完整部署 (推薦)
```bash
# 1. 複製範例配置
cp examples/vars-common.auto.tfvars terraform.tfvars
cp examples/vars-provider.auto.tfvars terraform.tfvars

# 2. 編輯配置檔案
vim terraform.tfvars
# 填入必要的 OCI 資訊

# 3. 初始化 Terraform
terraform init

# 4. 規劃部署
terraform plan

# 5. 執行部署
terraform apply
```

#### 方法二：使用預設配置檔
```bash
# 1. 使用 cluster-workers-only 配置
cd examples/profiles/cluster-workers-only

# 2. 設定變數
cp ../../vars-provider.auto.tfvars .
cp ../../vars-common.auto.tfvars .

# 3. 編輯配置
vim vars-provider.auto.tfvars
# 填入 tenancy_id, compartment_id, region

# 4. 部署
terraform init
terraform plan
terraform apply
```

#### 方法三：網路 + 叢集 + 工作節點
```bash
# 1. 使用 network-cluster-workers 配置
cd examples/profiles/network-cluster-workers

# 2. 設定變數
cp ../../vars-provider.auto.tfvars .
cp ../../vars-common.auto.tfvars .

# 3. 部署
terraform init
terraform plan
terraform apply
```

#### 方法四：ARM 架構部署 (推薦)
```bash
# 1. 使用 ARM 架構配置
cp examples/arm-config.tfvars terraform.tfvars

# 2. 編輯配置檔案
vim terraform.tfvars
# 填入必要的 OCI 資訊 (tenancy_id, compartment_id, region)

# 3. 部署
terraform init
terraform plan
terraform apply
```

### 進階配置

#### 自訂工作節點池
```hcl
worker_pools = {
  pool1 = {
    size = 4
    shape = {
      shape = "VM.Standard.A1.Flex"
      ocpus = 1
      memory = 6
      boot_volume_size = 46.6
    }
  }
  pool2 = {
    size = 2
    shape = {
      shape = "VM.Standard.A1.Flex"
      ocpus = 2
      memory = 12
    }
  }
}
```

#### 啟用擴展功能
```hcl
extensions = {
  prometheus = {
    enabled = true
  }
  cilium = {
    enabled = true
  }
  autoscaler = {
    enabled = true
  }
}
```

### 驗證部署

```bash
# 1. 取得 kubeconfig
terraform output -raw kubeconfig > kubeconfig

# 2. 設定 kubectl
export KUBECONFIG=kubeconfig

# 3. 驗證叢集
kubectl get nodes
kubectl get pods --all-namespaces

# 4. 測試部署
kubectl run nginx --image=nginx
kubectl get pods
```

### 清理資源

```bash
# 銷毀所有資源
terraform destroy

# 確認銷毀
terraform destroy -auto-approve
```

## 重要注意事項

1. **成本控制**: 部署後記得監控資源使用量
2. **安全性**: 預設為私有叢集，需要時才啟用公開存取
3. **備份**: 重要資料請設定適當的備份策略
4. **監控**: 建議啟用 Prometheus 監控
5. **更新**: 定期更新 Kubernetes 版本

## 故障排除

### 常見問題
- **認證錯誤**: 檢查 OCI API 金鑰設定
- **網路問題**: 確認 VCN 和子網路配置
- **權限不足**: 檢查 IAM 政策和動態群組
- **資源限制**: 確認租用戶資源配額

### 取得支援
- [官方文件](https://oracle-terraform-modules.github.io/terraform-oci-oke/)
- [GitHub Issues](https://github.com/oracle-terraform-modules/terraform-oci-oke/issues)

## 授權

Copyright (c) 2017, 2024 Oracle Corporation and/or its affiliates. Licensed under the [Universal Permissive License 1.0](./LICENSE).
