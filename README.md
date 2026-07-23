# GA Public Runner

该仓库只保存 GitHub Actions 调度工作流。实际 CTF 项目仍位于私人仓库，运行时通过只读 Deploy Key 拉取。

## 安全边界

- 私钥保存在 Actions Secret `PRIVATE_SOURCE_DEPLOY_KEY`，不是普通 Repository Variable。
- 私人仓库名和分支分别保存在变量 `PRIVATE_SOURCE_REPOSITORY`、`PRIVATE_SOURCE_REF`。
- Deploy Key 在私人仓库中只有读取权限。
- 工作流仅支持手动 `workflow_dispatch`，不使用 `pull_request_target`。
- 不要把含 token 的订阅地址填写到公开的 workflow inputs；优先使用私人仓库中已提交的节点池文件。
- 不要上传源码目录、`.git` 或包含密钥的文件作为 artifact。

## 工作流

- `Verify private source access`：只验证私人源码能否读取，不执行 live。
- `Build GA precompiled runtime cache`：一次性构建无密钥的 Python/Cloak/字体运行时 cache。
- `CTF GA own IP pool probe`：从私人仓库检出源码后执行现有 GA matrix 测试；支持 `legacy` / `prebuilt` 环境。
- `CTF GA target Graph healthy`：分批调用 own-IP workflow，直到累计达到目标 `Graph healthy` 数量或耗尽 slot 上限。

预构建说明见 `docs/GA_PRECOMPILED_RUNTIME.md`。
目标产出调度说明见 `docs/GA_TARGET_GRAPH_HEALTHY.md`。

## 当前私人源码配置

仓库和分支由 GitHub Repository Variables 管理，修改时无需编辑 workflow。

## 加密结果

公开仓库不能直接上传原始 `Results`，因为网络记录和运行日志可能包含账号或会话数据。工作流会先使用 RSA/CMS 加密，再上传 `.cms` artifact。

本机解密示例：

```powershell
.\tools\decrypt-ga-artifact.ps1 `
  -Artifact C:\path\ga-encrypted-xxx.zip `
  -PrivateKey C:\Users\wdnmd\Documents\outlook\OutlookRegister-main\OutlookRegister-repo\.local-secrets\ga-public-runner\results_private_key.pem
```

本机解密私钥不上传 GitHub。公开仓库只保存公钥证书。
