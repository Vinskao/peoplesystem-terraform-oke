# Keycloak 26 2FA 实施指南（Email + SMS OTP）

## 架构概览

```
用户登入
  ↓
用户名+密码认证 (1FA)
  ↓
选择 2FA 方式（浏览器提示）
  ├─→ Email OTP（邮箱验证码）
  ├─→ SMS OTP（手机简讯）
  └─→ App OTP（Google Authenticator，Keycloak 原生）
  ↓
输入验证码 ✓
  ↓
登入成功
```

---

## 第 1 步：部署 SPI 插件

### 1.1 选择 Email OTP 插件

推荐选项：
- **mesutpiskin/keycloak-2fa-email-authenticator** — 支持 Keycloak 24+，文档清晰
- **5-stones/keycloak-email-otp** — 开箱即用，无需编译

选 **mesutpiskin** 版本（更活跃维护）:
```bash
# clone 插件源码
git clone https://github.com/mesutpiskin/keycloak-2fa-email-authenticator.git
cd keycloak-2fa-email-authenticator
# 编译成 JAR
mvn clean package
# 输出: target/keycloak-2fa-email-authenticator-1.x.x.jar
```

### 1.2 选择 SMS OTP 插件

推荐：**keycloak-sms-provider-twilio** 或通用的 **keycloak-2fa-sms-authenticator**

选 Twilio 集成（国际标准）:
```bash
git clone https://github.com/your-org/keycloak-sms-provider.git
cd keycloak-sms-provider
mvn clean package
# 输出: target/keycloak-sms-provider-1.x.x.jar
```

> **注意**：SMS 插件需要在代码里内嵌 Twilio API key 或通过环境变数注入。后续在 Deployment 中配置。

### 1.3 在 K8s 中部署插件

编辑 `k8s/keycloak-deployment.yaml`，增加 init-container 或修改原 image:

**方案 A：构建含插件的自定义 image（推荐）**

创建 Dockerfile:
```dockerfile
FROM quay.io/keycloak/keycloak:26.1.4

# 复制编译好的 JAR 到 /opt/keycloak/providers/
COPY keycloak-2fa-email-authenticator-1.0.0.jar /opt/keycloak/providers/
COPY keycloak-sms-provider-1.0.0.jar /opt/keycloak/providers/

# 执行 build（激活插件）
RUN /opt/keycloak/bin/kc.sh build

USER 1000
```

构建并推送到你的 registry:
```bash
docker build -t your-registry/keycloak:26.1.4-with-2fa .
docker push your-registry/keycloak:26.1.4-with-2fa
```

然后更新 deployment:
```yaml
# k8s/keycloak-deployment.yaml
spec:
  template:
    spec:
      containers:
      - name: keycloak
        image: your-registry/keycloak:26.1.4-with-2fa  # 改这里
```

应用改动:
```bash
kubectl apply -f k8s/keycloak-deployment.yaml
```

Keycloak 会自动重启（Recreate strategy）。

**方案 B：通过 /providers PVC（可选，更灵活）**

如果希望不重建 image 就能更新插件:
```yaml
# k8s/keycloak-deployment.yaml
spec:
  template:
    spec:
      volumes:
      - name: providers
        persistentVolumeClaim:
          claimName: keycloak-providers-pvc
      containers:
      - name: keycloak
        volumeMounts:
        - name: providers
          mountPath: /opt/keycloak/providers
```

然后手动上传 JAR（通过 kubectl cp 或直接 mount）:
```bash
kubectl cp keycloak-2fa-email-authenticator-1.0.0.jar \
  keycloak-POD-ID:/opt/keycloak/providers/
kubectl restart -f k8s/keycloak-deployment.yaml
```

> 本指南采用 **方案 A**（构建自定义 image）为主。

---

## 第 2 步：配置 SMTP（Email OTP 必要）

登入 Keycloak Admin Console (`https://peoplesystem.tatdvsonorth.com/sso/admin/`)，选择你的 Realm（通常是 `master`）:

1. **Realm Settings** → **Email** 标籤页
2. 填入 SMTP 配置：
   ```
   From: noreply@peoplesystem.tatdvsonorth.com
   From Display Name: People System
   SMTP Server Host: smtp.gmail.com (或你的邮件服务器)
   SMTP Server Port: 587 (TLS) 或 465 (SSL)
   Encryption: STARTTLS 或 SSL
   Authentication: 启用
   SMTP Username: your-email@gmail.com
   SMTP Password: your-app-password (如用 Gmail，需申请 App Password)
   Test Email: 输入测试邮箱，发送测试邮件
   ```

3. 点 "Save" → 确认 "Test Email" 成功送达

> **Gmail 用户**：需到 [Google Account Security](https://myaccount.google.com/security) 启用 2FA，然后申请 App Password (16 位码)，用该码替代真实密码。

---

## 第 3 步：配置 SMS 网关

### 3.1 选择服务商

| 服务商 | 成本 | 支持地区 | 注意 |
|--------|------|--------|------|
| **Twilio** | $0.0075/SMS | 全球 | API 最成熟，有 free trial |
| **AWS SNS** | $0.01-0.02/SMS | 全球 | 需 AWS 账号，与 AWS 生态集成 |
| **Nexmo (Vonage)** | 类似 Twilio | 全球 | 台湾支持良好 |
| **台湾本地** | ~$1/SMS | 台湾 | 如 TIGO、AppWorks 等（需客制化） |

推荐 **Twilio**（开发体验最好，文档完善）。

### 3.2 Twilio 账号申请与配置

1. 注册 [Twilio](https://www.twilio.com/console) 账号，申请 free trial（送 $15 credit）
2. 获取：
   - **Account SID** — 在 Twilio Console 主页显示
   - **Auth Token** — 在 Twilio Console 主页显示
3. 申请虚拟电话号码（用作 From 号码）：
   - 进 Phone Numbers → Buy a Number
   - 选择支持 SMS 的号码（如美国 +1 开头）
   - 记下该号码

### 3.3 在 Keycloak 中配置 Twilio

修改 K8s deployment，注入 Twilio 凭证作为环境变数：

```yaml
# k8s/keycloak-deployment.yaml
env:
  # ... 既有的 env ...
  - name: TWILIO_ACCOUNT_SID
    valueFrom:
      secretKeyRef:
        name: twilio-credentials
        key: account-sid
  - name: TWILIO_AUTH_TOKEN
    valueFrom:
      secretKeyRef:
        name: twilio-credentials
        key: auth-token
  - name: TWILIO_FROM_NUMBER
    value: "+1234567890"  # 你的 Twilio 虚拟号码
  - name: SMS_LENGTH
    value: "6"  # OTP 长度
  - name: SMS_VALIDITY
    value: "600"  # OTP 有效期（秒），默认 10 分钟
```

创建 Secret:
```bash
kubectl create secret generic twilio-credentials \
  --from-literal=account-sid=ACxxxxxxxxxxxxxxx \
  --from-literal=auth-token=xxxxxxxxxxxxxxx \
  -n default
```

---

## 第 4 步：在 Realm 中配置认证流

登入 Admin Console，进入你的 Realm:

### 4.1 创建自定义认证流

1. **Authentication** → **Flows**
2. 点 **Create flow**，命名为 `browser-with-2fa`：
   ```
   名称: browser-with-2fa
   Flow Type: Basic Flow
   ```

3. 在该 Flow 中添加步骤（点 **Add Step**）：
   ```
   Step 1: Username Password Form (REQUIRED)
   Step 2: [Create a Subflow for 2FA Options]
   ```

4. 为 Step 2 创建 **Conditional Subflow**（命名 `2fa-options`）：
   ```
   Subflow Name: 2fa-options
   Flow Type: Conditional Subflow
   
   在这个 Subflow 内添加多个选项 (ADD AUTHENTICATOR):
   - Email OTP Authenticator (条件: 必须配置邮箱)
   - SMS OTP Authenticator (条件: 必须配置电话)
   - Authenticator App OTP (OPTIONAL, Keycloak 原生)
   - Recovery Codes (OPTIONAL)
   ```

   设置条件为 **CONDITIONAL**（用户可选择其一）。

### 4.2 绑定到登入流

1. **Authentication** → **Flows** → **Browser**
2. 点编辑，改 Step 1 的 Post-Login Flow 为你新建的 `browser-with-2fa`
3. 或直接替换默认 Browser Flow 的内容

### 4.3 配置用户 2FA 注册

用户登入后需在 **Account Management** 中注册 2FA:

1. **Realm Settings** → **User Registration** → 启用 `User Registration`
2. **Authentication** → **Required Actions**
   - 添加 "Configure OTP"（Keycloak 原生，用于 App OTP）
   - 添加 "Configure Email OTP"（来自你的插件）
   - 添加 "Configure SMS OTP"（来自你的插件）
   - 设置其中至少一个为 **ENABLED** 或 **DEFAULT**

---

## 第 5 步：测试 2FA 流

### 5.1 用户侧

1. 用浏览器打开 `https://peoplesystem.tatdvsonorth.com/sso`
2. 点 **Login**，输入用户名密码
3. 系统提示选择 2FA 方式（Email OTP 或 SMS OTP）
4. 选择 Email OTP：
   - 系统发送验证码到注册邮箱
   - 用户输入收到的 6 位数验证码
   - 登入成功 ✓
5. 选择 SMS OTP：
   - 系统发送验证码到注册手机
   - 用户输入收到的 6 位数验证码
   - 登入成功 ✓

### 5.2 管理侧（Admin Console）验证

```bash
# 查看 Keycloak 日志
ssh oke-node
kubectl logs keycloak-559994d657-m8t7q -f | grep -i "authenticator\|otp\|email\|sms"

# 验证插件已加载
kubectl exec keycloak-559994d657-m8t7q -- \
  ls -la /opt/keycloak/providers/ | grep -E "email|sms"
```

---

## 常见问题

### Q: 插件部署后没有出现在 Admin Console?
- 检查 `kc.sh build` 有没有执行（必须在 Dockerfile 中执行，不是可选的）
- 检查日志: `kubectl logs keycloak-POD | grep -i provider`

### Q: Email OTP 发送失败
- 确认 SMTP 配置已保存且 Test Email 成功
- 检查防火墙 / 网络是否阻止了 outbound SMTP 连接
- 如用 Gmail，验证 App Password 无误（不是真实密码）

### Q: SMS OTP 发送失败
- 确认 Twilio Account SID 和 Auth Token 正确
- 确认虚拟电话号码有效且有 SMS 权限（Trial 账号有限制）
- 检查用户注册时电话号码格式正确（应为 +1234567890 格式）

### Q: 用户卡在 2FA 选择界面？
- 确认用户已在 Account Management 中注册至少一种 2FA 方法
- 检查 Authentication Flow 的 REQUIRED/CONDITIONAL 设置是否正确

---

## 安全建议

1. **Secret 管理**：不要在 YAML 中硬编码 Twilio/SMTP 凭证，使用 K8s Secret 或 sealed-secret
2. **OTP 有效期**：默认 10 分钟，根据场景调整（不建议超过 15 分钟）
3. **OTP 长度**：默认 6 位，重要系统可考虑 8 位
4. **恢复码**：用户启用 2FA 时强制要求保存恢复码（防止手机丢失无法登入）
5. **HTTPS Only**：确保 `KC_PROXY_HEADERS: xforwarded` 和 Ingress TLS 已启用
6. **Rate Limiting**：考虑配置 OTP 发送频率限制（防止垃圾发送）

---

## 部署清单

- [ ] 选择和编译 Email OTP 插件
- [ ] 选择和编译 SMS OTP 插件
- [ ] 构建自定义 Keycloak image（含插件）
- [ ] 推送 image 到你的 registry
- [ ] 更新 K8s Deployment
- [ ] 创建 Twilio 账号并获取凭证
- [ ] 创建 K8s Secret (twilio-credentials)
- [ ] 更新 Deployment env 注入 Twilio 信息
- [ ] 配置 SMTP (Admin Console → Email)
- [ ] 创建认证流 (browser-with-2fa)
- [ ] 配置 Required Actions
- [ ] 测试用户注册 2FA
- [ ] 测试用户登入流程（Email OTP + SMS OTP）
- [ ] 验证日志和监控告警

---

## 下一步

1. **选择具体的 SPI 插件版本**（和你的 Keycloak 26 兼容）
2. **决定是否使用 Twilio** 还是其他 SMS 服务
3. **准备自定义 Dockerfile** 和 K8s manifests 更新
4. **安排测试用户** 进行 UAT

有任何问题或卡关，联系我补充细节。
