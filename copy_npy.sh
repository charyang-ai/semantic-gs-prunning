#!/bin/bash
# fix_poses_bounds.sh - 复制 poses_bounds.npy 到 fewshot 目录

ORIG_BASE="../data/LLFF"
FEWSHOT_BASE="../data/LLFF_fewshot"
scenes=("fern" "flower" "fortress" "horns" "leaves" "orchids" "room" "trex")

echo "=== 复制 poses_bounds.npy 到 Fewshot 目录 ==="

for scene in "${scenes[@]}"; do
    orig_file="${ORIG_BASE}/${scene}/poses_bounds.npy"
    fewshot_file="${FEWSHOT_BASE}/${scene}/poses_bounds.npy"
    
    if [ -f "$orig_file" ]; then
        cp "$orig_file" "$fewshot_file"
        echo "✓ ${scene}: poses_bounds.npy 已复制"
    else
        echo "⚠ ${scene}: 原始 poses_bounds.npy 不存在"
    fi
done

echo "=== 复制完成 ==="
