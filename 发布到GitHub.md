# 发布到 GitHub

## 已经准备好的内容

可以公开分享的干净包在：

```text
github-export\xhs-viral-decoder.zip
```

这个包已经排除了：

- 小红书采集数据
- 浏览器登录配置
- Python 本地环境
- Codex 私有上下文
- 临时截图预览

## 网页端上传方式

1. 打开 GitHub，创建一个新仓库。
2. 仓库名建议：`xhs-viral-decoder`。
3. 建议先设为 Private，确认没有敏感内容后再改 Public。
4. 解压 `github-export\xhs-viral-decoder.zip`。
5. 在 GitHub 仓库页面选择 `uploading an existing file`。
6. 把解压后的文件拖进去。
7. 提交信息可以写：`Initial release of Xiaohongshu viral decoder`。

## 命令行方式

如果本机已安装 Git 和 GitHub CLI：

```powershell
git init
git add .
git commit -m "Initial release of Xiaohongshu viral decoder"
gh repo create xhs-viral-decoder --private --source=. --remote=origin --push
```

确认内容无敏感信息后，可以在 GitHub 仓库设置里改成 Public。
