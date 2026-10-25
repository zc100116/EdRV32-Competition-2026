# AGENTS.md

本仓库的全部开发规则写在 `CLAUDE.md` 中，所有 agent（包括 Codex）都必须在开始工作前完整阅读并遵守。本文件只用于告诉 Codex 去读 `CLAUDE.md`，不另立规则。

特别注意 `CLAUDE.md` 第 12 节：只实现规格和 Task 要求的内容；不加没有被要求的防御性检查、兜底路径、哈希校验和门禁；出错就明确报错。认为需要额外保护时，先提问，不要自行添加。

All development rules for this repository live in `CLAUDE.md`. Read it in full before starting any work and follow it; this file adds no rules of its own. Pay particular attention to section 12: implement only what the spec and the task require — no unrequested defensive checks, fallbacks, hash verification or gates; fail loudly; ask before adding any protection.
