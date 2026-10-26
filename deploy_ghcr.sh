#!/usr/bin/env bash
# Deploy the verified amd64 GHCR release on Debian. Run with sudo bash.
set -Eeuo pipefail
umask 077

RELEASE=45c0125498d226104b16e4740dfbdd9cdaf562c7
CONFIG_RELEASE=53ca677a0b436162392d83a3f5d0782814fc0cf5
REPOSITORY=ZYaosheng/xianyu-auto-reply
INSTALL_DIR=/opt/xianyu-managed
PROJECT=xianyu-managed
temporary_file=''

cleanup() {
  if [[ -n "$temporary_file" ]]; then rm -f -- "$temporary_file"; fi
}
trap cleanup EXIT
trap 'printf "\n部署在第 %s 行停止。请把错误输出发来排查；已有数据已保留。\n" "$LINENO" >&2' ERR

die() { printf '错误：%s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die '请使用 sudo bash deploy_ghcr.sh 执行。'
[[ $(uname -m) == x86_64 ]] || die '当前镜像仅支持 x86_64 / amd64。'
for executable in docker curl openssl ss awk mktemp; do
  command -v "$executable" >/dev/null || die "缺少命令：$executable，请安装后重试。"
done
docker info >/dev/null
docker compose version

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

if [[ ! -e .env ]]; then
  echo '首次部署：生成密码和内部 API token。'
  # Generate each value separately so a failed openssl command stops deployment.
  mysql_root_password=$(openssl rand -hex 32)
  mysql_password=$(openssl rand -hex 32)
  redis_password=$(openssl rand -hex 32)
  internal_api_token=$(openssl rand -hex 32)
  temporary_file=$(mktemp "$INSTALL_DIR/.env.XXXXXX")
  cat > "$temporary_file" <<EOF
IMAGE_PREFIX=ghcr.io/zyaosheng/xianyu-auto-reply
IMAGE_TAG=sha-${RELEASE}
FRONTEND_PORT=19000
MYSQL_ROOT_PASSWORD=${mysql_root_password}
MYSQL_PASSWORD=${mysql_password}
REDIS_PASSWORD=${redis_password}
INTERNAL_API_TOKEN=${internal_api_token}
EOF
  mv -- "$temporary_file" .env
  temporary_file=''
else
  echo '使用已有 .env，保留原密码、端口及镜像版本。'
fi
chmod 600 .env

# Read only the numeric port; never execute the contents of .env.
port=$(awk -F= '/^FRONTEND_PORT=/{sub(/\r$/, "", $2); print $2}' .env)
[[ $port =~ ^[0-9]{1,5}$ ]] || die '.env 中的 FRONTEND_PORT 必须是纯数字。'
port=$((10#$port))
(( port >= 1 && port <= 65535 )) || die 'FRONTEND_PORT 必须在 1 到 65535 之间。'

# Pin deployment fixes independently of the already verified application images.
temporary_file=$(mktemp "$INSTALL_DIR/.compose.XXXXXX")
curl -fL --retry 3 --connect-timeout 15 --max-time 180 \
  "https://raw.githubusercontent.com/${REPOSITORY}/${CONFIG_RELEASE}/docker-compose.ghcr.yml" \
  -o "$temporary_file"
docker compose --project-name "$PROJECT" --env-file .env -f "$temporary_file" config --quiet
mv -- "$temporary_file" docker-compose.ghcr.yml
temporary_file=''

compose=(docker compose --project-name "$PROJECT" --env-file .env -f docker-compose.ghcr.yml)
frontend_id=$("${compose[@]}" ps --status running -q frontend)
listeners=$(ss -H -lnt)
if awk -v port="$port" '$4 ~ (":" port "$") {found=1} END {exit !found}' <<< "$listeners"; then
  [[ -n "$frontend_id" ]] || die "端口 $port 已被占用。修改 $INSTALL_DIR/.env 中的 FRONTEND_PORT 后重试。"
  # Only allow reuse when this project's frontend actually publishes this port.
  bindings=$(docker port "$frontend_id" 80/tcp)
  awk -v port="$port" '$0 ~ (":" port "$") {found=1} END {exit !found}' <<< "$bindings" \
    || die "端口 $port 被其他服务占用，请修改 FRONTEND_PORT。"
fi

echo '拉取四个应用镜像及 MySQL、Redis……'
if ! "${compose[@]}" pull; then
  printf '\n拉取失败。如果提示 denied/unauthorized，请将四个 GHCR 包设为 Public，\n或在 root 下执行 docker login ghcr.io 后重试。网络错误则检查 NAS 的 GHCR 连接。\n' >&2
  exit 1
fi

echo '启动项目并等待健康检查……'
if ! "${compose[@]}" up -d --wait --wait-timeout 900; then
  "${compose[@]}" ps --all
  printf '\n启动未完成，查看日志：\ncd %s && docker compose -p %s -f docker-compose.ghcr.yml logs --tail=100\n' "$INSTALL_DIR" "$PROJECT" >&2
  exit 1
fi
"${compose[@]}" ps
curl --fail --silent --show-error --retry 5 --retry-delay 3 --retry-connrefused \
  --connect-timeout 5 --max-time 15 "http://127.0.0.1:${port}/health"
printf '\n部署完成。访问：http://你的NAS局域网IP:%s\n配置目录：%s\n' "$port" "$INSTALL_DIR"
