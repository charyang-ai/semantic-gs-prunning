#!/bin/bash
# ============================================================================
# LLFF 少样本数据子集创建脚本 (最终可用版本)
# 核心修复：按排序后的文件列表位置采样，不假设文件名格式
# ============================================================================

DATA_BASE="../data/LLFF"
FEWSHOT_BASE="../data/LLFF_fewshot"
NUM_VIEWS=5

scenes=("fern" "flower" "fortress" "horns" "leaves" "orchids" "room" "trex")

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "============================================================"
echo -e "${BLUE}  LLFF 少样本数据子集创建脚本 (最终可用版)${NC}"
echo "============================================================"
echo "  开始时间：$(date '+%Y-%m-%d %H:%M:%S')"
echo "  源数据：${DATA_BASE}"
echo "  输出目录：${FEWSHOT_BASE}"
echo "  训练视图：${NUM_VIEWS}"
echo "============================================================"

mkdir -p "${FEWSHOT_BASE}"

success_count=0
error_count=0

for scene in "${scenes[@]}"; do
    echo ""
    echo "------------------------------------------------------------"
    echo -e "处理场景：${GREEN}${scene}${NC}"
    echo "------------------------------------------------------------"
    
    src_dir="${DATA_BASE}/${scene}"
    dst_dir="${FEWSHOT_BASE}/${scene}"
    
    if [ ! -d "$src_dir" ]; then
        echo -e "${RED}✗ 源目录不存在${NC}"
        ((error_count++))
        continue
    fi
    
    # 查找图像目录
    img_src=""
    for dir_name in "images" "images_4" "images_2" "images_8"; do
        if [ -d "${src_dir}/${dir_name}" ]; then
            img_src="${src_dir}/${dir_name}"
            echo "  ℹ 图像目录：${dir_name}"
            break
        fi
    done
    
    if [ -z "$img_src" ]; then
        echo -e "${RED}✗ 未找到图像目录${NC}"
        ((error_count++))
        continue
    fi
    
    # ✅ 核心修复：获取排序后的实际文件列表（数组）
    mapfile -t all_images < <(find "$img_src" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) | sort)
    
    img_count=${#all_images[@]}
    echo "  总图像数：${img_count}"
    
    if [ "$img_count" -eq 0 ]; then
        echo -e "${RED}✗ 未找到图像${NC}"
        ((error_count++))
        continue
    fi
    
    # 计算采样位置
    if [ "$img_count" -lt "$NUM_VIEWS" ]; then
        NUM_ACTUAL=$img_count
    else
        NUM_ACTUAL=$NUM_VIEWS
    fi
    
    # 均匀采样位置索引
    step=$((img_count / NUM_ACTUAL))
    start=$((step / 2))
    
    echo "  采样位置:"
    selected_indices=()
    for ((i=0; i<NUM_ACTUAL; i++)); do
        idx=$((start + i * step))
        if [ "$idx" -lt "$img_count" ]; then
            selected_indices+=($idx)
            echo "    [$idx] $(basename "${all_images[$idx]}")"
        fi
    done
    
    # 创建目录
    mkdir -p "${dst_dir}/images" "${dst_dir}/sparse/0" "${dst_dir}/masks"
    
    # 复制 COLMAP
    if [ -d "${src_dir}/sparse/0" ]; then
        cp "${src_dir}/sparse/0"/* "${dst_dir}/sparse/0/" 2>/dev/null
        echo "    ✓ COLMAP"
    fi
    
    # 复制 match_data
    if [ -f "${src_dir}/match_data.npy" ]; then
        cp "${src_dir}/match_data.npy" "${dst_dir}/"
        echo "    ✓ match_data.npy"
    fi
    
    # ✅ 核心修复：按数组位置复制实际文件
    echo "  复制图像..."
    for idx in "${selected_indices[@]}"; do
        img_file="${all_images[$idx]}"
        if [ -f "$img_file" ]; then
            cp "$img_file" "${dst_dir}/images/"
            echo "    ✓ $(basename "$img_file")"
        else
            echo -e "${YELLOW}    ⚠ 文件不存在：${idx}${NC}"
        fi
    done
    
    # 生成配置
    cat > "${dst_dir}/fewshot_config.txt" << EOF
scene: ${scene}
total: ${img_count}
train_views: ${NUM_ACTUAL}
indices: ${selected_indices[*]}
files: $(for idx in "${selected_indices[@]}"; do basename "${all_images[$idx]}"; done | tr '\n' ' ')
EOF
    echo "    ✓ fewshot_config.txt"
    
    echo -e "${GREEN}✓ 完成：${scene}${NC}"
    ((success_count++))
done

echo ""
echo "============================================================"
echo -e "${BLUE}  统计${NC}"
echo "============================================================"
echo -e "  成功：${GREEN}${success_count}${NC} | 错误：${RED}${error_count}${NC}"
echo "  输出：${FEWSHOT_BASE}/"
echo "============================================================"

# 验证
if [ $success_count -gt 0 ]; then
    echo ""
    echo "=== 验证 fern 场景 ==="
    ls -lh "${FEWSHOT_BASE}/fern/images/"
    echo ""
    cat "${FEWSHOT_BASE}/fern/fewshot_config.txt"
fi

exit 0
