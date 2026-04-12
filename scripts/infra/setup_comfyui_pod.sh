#!/bin/bash
# setup_comfyui_pod.sh — RunPod pytorch イメージ上で ComfyUI を起動するセットアップスクリプト
#
# 背景:
#   RunPod の comfyui テンプレートイメージは起動時に ComfyUI を自動起動するが、
#   ネットワークボリューム上の venv が Python 3.12 に依存しているため
#   pytorch イメージ (Python 3.10) では起動に失敗する。
#   このスクリプトは Python 3.12 をインストールし、ComfyUI を手動起動する。
#
# 前提:
#   - RunPod pytorch イメージ (例: runpod/pytorch:2.1.0-py3.10-cuda11.8.0-devel-ubuntu22.04)
#   - ネットワークボリュームに ComfyUI がインストール済み (/workspace/runpod-slim/ComfyUI)
#   - venv (.venv-cu128) が Python 3.12 ベースで構築済み
#
# 使い方:
#   1. Pod 作成時にネットワークボリュームをマウント
#   2. Pod 起動後に SSH または vdsl_task_run で実行:
#        bash /workspace/setup_comfyui.sh
#   3. 約 30 秒後に ComfyUI が :8188 で応答開始
#
#   vdsl MCP からの実行例:
#     vdsl_task_run(pod_id="xxx", command="bash /workspace/setup_comfyui.sh")
#     vdsl_connect(pod_id="xxx", wait=true)
#
# ネットワークボリューム上への配置:
#   このスクリプトを /workspace/setup_comfyui.sh にコピーしておくと
#   Pod を Stop→Start した際にすぐ復帰できる。
#
# 所要時間:
#   - 初回 (Python 3.12 インストール込み): 約 3-5 分
#   - 2回目以降 (Python 3.12 キャッシュ済み): 約 30 秒

set -e
export DEBIAN_FRONTEND=noninteractive
export TZ=UTC
echo "[setup] Starting ComfyUI setup..."

# Install Python 3.12 if missing
if ! command -v python3.12 &>/dev/null; then
  echo "[setup] Installing Python 3.12..."
  while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
    echo "[setup] Waiting for apt lock..."
    sleep 3
  done
  apt-get update -qq
  apt-get install -y -qq software-properties-common
  add-apt-repository -y ppa:deadsnakes/ppa
  apt-get update -qq
  apt-get install -y -qq python3.12 python3.12-venv python3.12-dev
  echo "[setup] Python 3.12 installed."
else
  echo "[setup] Python 3.12 already available."
fi

# Start ComfyUI
echo "[setup] Starting ComfyUI..."
cd /workspace/runpod-slim/ComfyUI
nohup .venv-cu128/bin/python main.py --listen 0.0.0.0 --port 8188 > /workspace/runpod-slim/comfyui_manual.log 2>&1 &
echo "[setup] ComfyUI PID: $!"
echo "[setup] Done. ComfyUI should be ready in ~30s."
