# GitHub Actions → GHCR → Debian

## 发布镜像

将本地变更推送到你自己的仓库 `main` 分支，或在 Actions 手动运行
`Build GHCR images`。Fork 后如 Actions 被禁用，先在仓库 Actions 页面启用。
工作流使用 `GITHUB_TOKEN` 发布，不需要提供个人令牌。

等待 backend-web、websocket、scheduler、frontend 四个任务全部成功。
镜像名为 `ghcr.io/<小写账号>/<小写仓库名>-<服务名>:sha-<完整提交SHA>`。
目前只构建 `linux/amd64`，适用于 x86_64 Debian；ARM64 需要另行调整并验证。

首次发布后，如需 Debian 匿名拉取，请在 GitHub Packages 中将四个包设为 Public。
私有包需要在 Debian 使用具备 `read:packages` 权限的令牌登录 GHCR：

```bash
docker login ghcr.io -u YOUR_GITHUB_USERNAME
```

## 首次部署

### NAS 脚本部署（默认 19000 端口）

仓库根目录的 `deploy_ghcr.sh` 自动下载已经验证构建成功的版本配置，生成随机密码，
检查端口，拉取镜像并等待健康检查。以 root 或 `sudo bash deploy_ghcr.sh` 运行。
要求已有 Docker Compose、curl、openssl、ss，适用于 x86_64 Debian。

安装目录为 `/opt/xianyu-managed`。重复运行保留已有 `.env` 的密码、端口和镜像版本。
端口冲突时修改该目录 `.env` 中的 `FRONTEND_PORT` 后重试。
首次部署使用提交 `45c0125498d226104b16e4740dfbdd9cdaf562c7` 的镜像；
后续更新仍需等待新的四个镜像全部成功后再修改 `IMAGE_TAG`。

### 手动部署

把本仓库的 `docker-compose.ghcr.yml`、`.env.ghcr.example` 放入 Debian 上
独立的新目录，例如 `/opt/xianyu-managed`，进入该目录执行：

```bash
cp .env.ghcr.example .env
chmod 600 .env
nano .env
```

填写小写 `IMAGE_PREFIX`、成功构建对应的 `IMAGE_TAG`。
用 `openssl rand -hex 32` 分别生成四个随机值，填入 MySQL root 密码、
MySQL 应用密码、Redis 密码、内部 API token。保留这些配置用于后续更新。
前端默认 9000 端口，部署前确认该端口空闲，或修改 `FRONTEND_PORT`。

```bash
docker compose -f docker-compose.ghcr.yml config --quiet
docker compose -f docker-compose.ghcr.yml pull
docker compose -f docker-compose.ghcr.yml up -d --wait --wait-timeout 300
docker compose -f docker-compose.ghcr.yml ps
curl -f http://127.0.0.1:9000/health
```

若修改前端端口，最后一条命令也要使用对应端口。
浏览器访问 `http://Debian地址:9000`。

部署包含 MySQL、Redis 和四个应用服务；返佣子系统不在本次构建范围。
数据库、日志、上传文件和浏览器数据使用 `xianyu-managed` 项目的独立命名卷。
只发布前端端口，其他服务通过项目内部网络通信。

## 更新

推送修改，等四个构建任务全部成功，再修改 Debian `.env` 中的 `IMAGE_TAG`，执行：

```bash
docker compose -f docker-compose.ghcr.yml pull
docker compose -f docker-compose.ghcr.yml up -d --wait --wait-timeout 300
docker compose -f docker-compose.ghcr.yml ps
```

镜像标签可用于追溯代码版本；如更新包含数据库迁移，换回旧镜像不等同于恢复数据库。
不要执行全局 Docker 清理命令或带 `-v` 的 down 命令来更新本项目。

## 故障日志

```bash
docker compose -f docker-compose.ghcr.yml logs --tail=100 backend-web websocket scheduler
```

原仓库的 `deploy.sh` / `update.sh` 会生成原作者镜像配置，本流程使用上述独立文件。
本地仅完成配置检查，实际镜像构建和启动仍需 Actions 与 Debian 验证。
