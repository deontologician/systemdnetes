#!/usr/bin/env bash
set -euo pipefail

REMOTE="${1:?Usage: $0 <remote-host> [container|worker|all]}"
TARGET="${2:-all}"
REMOTE_DIR="~/Code/systemdnetes"

build_container() {
  echo "Building orchestrator image on $REMOTE..."
  ssh "$REMOTE" "cd $REMOTE_DIR && git pull --ff-only && nix build .#container --out-link result"
  local store_path
  store_path=$(ssh "$REMOTE" "readlink -f $REMOTE_DIR/result")
  echo "Copying $store_path..."
  rm -f result
  scp "$REMOTE:$store_path" result
}

build_worker() {
  echo "Building worker image on $REMOTE..."
  ssh "$REMOTE" "cd $REMOTE_DIR && git pull --ff-only && nix build .#worker --out-link result-worker"
  local store_path
  store_path=$(ssh "$REMOTE" "readlink -f $REMOTE_DIR/result-worker")
  echo "Copying $store_path..."
  rm -f result-worker
  scp "$REMOTE:$store_path" result-worker
}

case "$TARGET" in
  container) build_container ;;
  worker)    build_worker ;;
  all)       build_container; build_worker ;;
  *)         echo "Unknown target: $TARGET (use container, worker, or all)" >&2; exit 1 ;;
esac

echo "Done. Images ready for skopeo copy."
