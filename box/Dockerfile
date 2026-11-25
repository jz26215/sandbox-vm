FROM node:22-bookworm-slim
# 基础工具 + Claude Code / Codex 需要的依赖（ripgrep 搜代码；pip/venv 装 Python 库；build-essential=gcc/make）
RUN apt-get update \
 && apt-get install -y --no-install-recommends tzdata ca-certificates curl git bash python3 python3-pip python3-venv build-essential ripgrep less procps \
 && rm -rf /var/lib/apt/lists/*
# 装在镜像里（根文件系统只读，运行时改不了）；升级 = 重建镜像
RUN npm install -g @anthropic-ai/claude-code @openai/codex && npm cache clean --force
# node 镜像自带 uid 1000 用户；HOME=/sandbox，登录信息存在 data/ 里，重建不丢
# VS Code 连进来时按系统用户表找家目录 → 指到 /sandbox（可写）
RUN usermod -d /sandbox node
USER 1000:1000
WORKDIR /sandbox
CMD ["sleep", "infinity"]
