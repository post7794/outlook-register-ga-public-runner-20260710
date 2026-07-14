# GA 预构建运行环境

## 目标

GA hosted runner 是一次性虚拟机。旧路径每个 live slot 都重复执行：

```text
apt/fonts        中位约 46s
pip/Cloak        中位约 24s
font alias       中位约 2s
合计             中位约 72s
```

预构建方案把以下无账号、无密钥的公共依赖放进 GitHub Actions cache：

```text
.venv
~/.cloakbrowser
~/.local/share/fonts/ga-runtime
```

私有注册源码、账号、证书私钥、API Key 和 evidence 不进入 cache。

## 构建

先运行：

```text
Build GA precompiled runtime cache
cache_revision=v1
runner=ubuntu-22.04
```

对应 workflow：

```text
.github/workflows/build-ga-runtime-cache.yml
```

cache key：

```text
Linux-X64-ga-runtime-v1-py310-cloak048
```

Cache 不覆盖更新。Python 包、Cloak/Chromium 或字体配方变化时，必须把 revision 改为 `v2`、`v3`。

## 使用

`ctf-ga-own-ip-pool.yml` 新增：

```text
runtime_mode=legacy|prebuilt
runtime_cache_revision=v1
```

初始默认保持 `legacy`。先用 1–5 个 slot 验证：

- cache restore 成功；
- Python/Cloak/Chromium 版本一致；
- `Segoe UI`、`Calibri` font match 正常；
- HumanCaptcha、strict success 和 Graph 入库没有行为退化；
- `Restore + Validate` 明显快于旧环境的约 72s。

验证完成后再把默认切到 `prebuilt`。

## 边界

预构建只消除环境准备时间。它不能缩短：

- GA runner 排队；
- `final_only` 协调等待；
- HumanCaptcha / fresh rechallenge；
- Graph OAuth 与 Inbox 探针。

因此它预计能缩短每一波 live jobs 的冷启动，但不会让总墙钟按 72 秒 × slot 数线性下降。

## 回滚

dispatch 时设置：

```text
runtime_mode=legacy
```

即可恢复原来的 apt/pip 安装路径，不需要回滚源码。
