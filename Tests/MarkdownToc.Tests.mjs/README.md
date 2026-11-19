# MarkdownToc.Tests 回归入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

[实际测试脚本](./MarkdownToc.Tests.mjs)验证同包功能的接口和边界；保留原回归协议，不增加重复确认。

## 一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在当前脚本包目录运行，保留完整功能目录以定位被测源码：

```shell
node --test "./MarkdownToc.Tests.mjs"
```

使用已有 Node.js 原生测试运行器，不因目录包装安装或升级环境。各平台、GUI、SDK和网络分支的依赖及取消条件以用例声明为准；未满足的条件不能当作测试通过。

## 二、覆盖项与结果 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- `repository boundaries compare directory identity instead of path spelling`
- `management commands reject a tool copied below the repository root`
- `both distributed entry points manage a repository without changing its index or parent config`
- `clean is idempotent; smudge restores the complete original source`
- `documents without an active TOC are returned byte for byte`
- `existing generated TOC updates after headings are added, renamed, or removed`
- `Chinese headings, repeated headings, and skipped levels get working targets`
- `H1 is unchanged and omitted from the TOC even when H2 repeats its text`
- `ordinary underscores, inline code, and tabs keep their displayed text`
- `only H2 through H6 and single-line Setext headings are included with exact roundtrip`
- `code examples, comments, frontmatter, and raw HTML do not create headings or TOCs`
- `inline formatting is converted to safe plain labels and explicit IDs win`
- `empty HTML anchors use an automatically generated target`
- `font IDs, duplicate IDs, and nested inline spans get reliable targets and exact roundtrip`
- `explicit IDs duplicated by H1 or prose use owned heading anchors instead`
- `multiple case-insensitive TOCs preserve their original indentation and trailing spaces`
- `nested link brackets keep CDN and GitHub labels without leaking their URLs`
- `damaged owned heading anchors are rejected instead of silently editing the source`
- `legacy generated blocks migrate to v2 while unrelated source remains intact`
- `clean and smudge CLI reject malformed UTF-8 before returning any output`
- `unrelated disclosure blocks survive both transformations`
- `BOM, CRLF, trailing newlines, and a first-line TOC are preserved`
- `damaged generated markers stop conversion`
- `Git stages generated content while worktree and checkout retain the Typora token`
- `manifest installation, index checks, checkout, and uninstall cover every listed file`
- `invalid manifest paths and schemas fail before installation changes local config`
- `manifest installation does not follow document symlinks or cross nested Git roots`
- `index check rejects stale generated content even when worktree content is correct`
- `partial staging can make a stale TOC and index check catches either separated hunk`
- `install preserves a pre-existing filter configuration and rejects a conflicting owner`

终端输出通过、失败和跳过；非零退出表示失败。临时夹具、日志及子进程按用例输出定位。目录迁移与语法检查不代表真实安装、设备、GUI或目标系统业务已验收。

[返回测试目录](../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
