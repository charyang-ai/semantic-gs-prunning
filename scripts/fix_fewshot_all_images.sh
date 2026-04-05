#!/bin/bash
# fix_fewshot_all_images.sh - 复制所有原始图像解决 COLMAP 引用问题

FEWSHOT_BASE="../../data/LLFF_fewshot"
ORIG_BASE="../../data/LLFF"
scenes=("fern" "flower" "fortress" "horns" "leaves" "orchids" "room" "trex")

echo "=== 复制所有原始图像到 Fewshot 目录 ==="

for scene in "${scenes[@]}"; do
    echo "处理：$scene"
    
    # 查找原始图像目录
    orig_img=""
    for dir in "images" "images_4" "images_2" "images_8"; do
        if [ -d "${ORIG_BASE}/${scene}/${dir}" ]; then
            orig_img="${ORIG_BASE}/${scene}/${dir}"
            break
        fi
    done
    
    if [ -z "$orig_img" ]; then
        echo "  ✗ 未找到原始图像目录"
        continue
    fi
    
    fewshot_img="${FEWSHOT_BASE}/${scene}/images"
    mkdir -p "$fewshot_img"
    
    # 复制所有原始图像（保留已有文件）
    cp -n "${orig_img}"/* "${fewshot_img}/" 2>/dev/null
    
    # 恢复原始 COLMAP 结果
    if [ -d "${ORIG_BASE}/${scene}/sparse/0" ]; then
        rm -rf "${FEWSHOT_BASE}/${scene}/sparse/0"
        cp -r "${ORIG_BASE}/${scene}/sparse/0" "${FEWSHOT_BASE}/${scene}/sparse/0"
    fi
    
    # 统计
    img_count=$(find "$fewshot_img" -maxdepth 1 -type f -iname "*.jpg" | wc -l)
    echo "  ✓ 图像数：$img_count"
done

echo "=== 修复完成 ==="
