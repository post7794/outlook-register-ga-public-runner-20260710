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
runner=ubuntu-22.04 或 ubuntu-24.04
```

对应 workflow：

```text
.github/workflows/build-ga-runtime-cache.yml
```

cache key 按 runner 的 Python ABI 隔离：

```text
ubuntu-22.04: Linux-X64-ga-runtime-v1-py310-cloak048
ubuntu-24.04: Linux-X64-ga-runtime-v1-py312-cloak048
```

不能跨 runner 复用 venv。24.04 的系统 Python 是 3.12；若误恢复 py310
cache，activate 脚本虽然能执行，但包 metadata 不在 3.12 的搜索路径中，
runtime validation 会在触碰注册目标前失败。

Cache 不覆盖更新。Python 包、Cloak/Chromium 或字体配方变化时，必须把 revision 改为 `v2`、`v3`。

## 使用

`ctf-ga-own-ip-pool.yml` 新增：

```text
runtime_mode=legacy|prebuilt
runtime_cache_revision=v1
```

已通过 5-slot 小样本验证，当前默认已切到 `prebuilt`。验证标准：

- cache restore 成功；
- Python/Cloak/Chromium 版本一致；
- `Segoe UI`、`Calibri` font match 正常；
- HumanCaptcha、strict success 和 Graph 入库没有行为退化；
- `Restore + Validate` 明显快于旧环境的约 72s。

上述生产验证针对 `ubuntu-22.04`。`ubuntu-24.04` 必须先单独构建并验证
`py312` cache，不能把 22.04 的结果外推到 24.04。

实测 `Restore + Validate` 为 8–12 秒，旧环境约 72 秒；3 个 live slots 中 2 个 strict success 且 2 个 Graph healthy，未观察到环境技术失败。

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
