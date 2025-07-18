# Move To Learn NFT 项目说明

## 1. Aptos CLI 初始化

```bash
aptos init
```

- 选择网络：`testnet`
- 私钥输入：可留空自动生成
- 账户信息会保存在 `.aptos/config.yaml`

**注意：私钥务必妥善保管，泄露即丢失资产！**

---

## 2. 领取测试币

1. 访问 CLI 输出的 faucet 链接领取测试币  
   例如：https://aptos.dev/network/faucet?address=你的账户地址
2. 领取后，查询余额：

```bash
aptos account balance
```

- 1 APT = 100,000,000 Octa

---

## 3. `.aptos/config.yaml` 说明

```yaml
profiles:
  default:
    network: Testnet
    private_key: ed25519-priv-0x...
    public_key: ed25519-pub-0x...
    account: 你的账户地址
    rest_url: "https://fullnode.testnet.aptoslabs.com"
```

- `private_key`：账户私钥，务必保密
- `public_key`：账户公钥，可公开
- `account`：Aptos 账户地址
- `rest_url`：Aptos 节点 API 地址

---

## 4. Move 合约编译

```bash
aptos move compile
```

- 首次编译会自动拉取依赖
- 若有未使用变量警告，可忽略或按提示优化

---

## 5. Move 合约发布

```bash
aptos move publish --assume-yes
```

- 发布成功后会输出交易哈希，可在区块链浏览器查询
- 典型输出示例：

```json
{
  "Result": {
    "transaction_hash": "0x...",
    "gas_used": 4668,
    "gas_unit_price": 100,
    "sender": "你的账户地址",
    "sequence_number": 0,
    "success": true,
    "timestamp_us": 1752651565396134,
    "version": 6809603678,
    "vm_status": "Executed successfully"
  }
}
```

### 字段解释

- `transaction_hash`：交易哈希，可用于区块链浏览器查询
- `gas_used`：本次交易消耗的 gas 数量
- `gas_unit_price`：每单位 gas 的价格
- `sender`：发起交易的钱包地址
- `sequence_number`：账户发起的第几笔交易（从 0 开始）
- `success`：交易是否成功
- `timestamp_us`：链上确认时间（微秒）
- `version`：区块链版本号/区块高度
- `vm_status`：虚拟机执行状态

---

## 6. 常见问题

- **私钥安全**：请勿泄露私钥，建议使用密码管理工具保存
- **测试币领取**：未领取测试币无法发布合约
- **合约编译警告**：如遇未使用变量警告，可按提示优化代码

---

如有更多问题，请查阅 [Aptos 官方文档](https://aptos.dev/)。

---
