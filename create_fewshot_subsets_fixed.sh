#!/bin/bash
# ============================================================================
# LLFF 少样本数据子集创建脚本 (修复版)
# 修复: 图像检测/八进制错误/语法错误
# ============================================================================

# 配置
DATA_BASE="../data/LLFF"
FEWSHOT_BASE="../data/LLFF_fewshot"
NUM_VIEWS=5
SAMPLING_STRATEGY="uniform"

scenes=("fern" "flower" "fortress" "horns" "leaves" "orchids" "room" "trex")

# 颜色
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "============================================================"
echo -e "${BLUE}  LLFF 少样本数据子集创建脚本 (修复版)${NC}"
echo "============================================================"
echo "  开始时间：$(date '+%Y-%m-%d %H:%M:%S')"
echo "  源数据目录：${DATA_BASE}"
echo "  输出目录：${FEWSHOT_BASE}"
echo "============================================================"

mkdir -p "${FEWSHOT_BASE}"

success_count=0
error_count=0

# ============================================================================
# 辅助函数：均匀采样索引 (返回十进制整数数组)
# ============================================================================

sample_indices_uniform() {
    local total=$1
    local num_samples=$2
    
    if [ "$total" -le "$num_samples" ]; then
        for ((i=0; i<total; i++)); do echo $i; done
    else
        local step=$((total / num_samples))
        local start=$((step / 2))
        for ((i=0; i<num_samples; i++)); do
            local idx=$((start + i * step))
            if [ "$idx" -lt "$total" ]; then
                echo $idx  # 输出十进制整数，不带前导零
            fi
        done
    fi
}

# ============================================================================
# 辅助函数：查找图像文件 (修复扩展名大小写问题)
# ============================================================================

find_image_file() {
    local img_dir=$1
    local index=$2  # 十进制整数，如 18
    
    # 格式化文件名: 支持 5位(00018) 或 6位(000018)
    for digits in 5 6; do
        local fmt=$(printf "%0${digits}d" $index)
        for ext in jpg jpeg png JPG JPEG PNG; do
            local candidate="${img_dir}/${fmt}.${ext}"
            if [ -f "$candidate" ]; then
                echo "$candidate"
                return 0
            fi
        done
    done
    return 1
}

# ============================================================================
# 主流程
# ============================================================================

echo ""
echo "=== 创建少样本子集 ==="

for scene in "${scenes[@]}"; do
    echo ""
    echo "------------------------------------------------------------"
    echo -e "处理场景: ${GREEN}${scene}${NC}"
    echo "------------------------------------------------------------"
    
    src_dir="${DATA_BASE}/${scene}"
    dst_dir="${FEWSHOT_BASE}/${scene}"
    
    # 检查源目录
    if [ ! -d "$src_dir" ]; then
        echo -e "${RED}✗ 源目录不存在: ${src_dir}${NC}"
        ((error_count++))
        continue
    fi
    
    # 查找图像目录 (支持多种命名)
    img_src=""
    for dir_name in "images" "images_4" "images_2" "images_8"; do
        if [ -d "${src_dir}/${dir_name}" ]; then
            img_src="${src_dir}/${dir_name}"
            echo "  ℹ 使用图像目录: ${dir_name}"
            break
        fi
    done
    
    if [ -z "$img_src" ] || [ ! -d "$img_src" ]; then
        echo -e "${RED}✗ 未找到图像目录${NC}"
        echo "  尝试路径: ${src_dir}/images{,_4,_2,_8}"
        ((error_count++))
        continue
    fi
    
    # ✅ 修复: 统计图像 (不区分大小写扩展名)
    img_count=$(find "$img_src" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.png" -o -iname "*.jpeg" \) 2>/dev/null | wc -l)
    echo "  总图像数: ${img_count}"
    
    if [ "$img_count" -lt "$NUM_VIEWS" ]; then
        echo -e "${YELLOW}⚠ 图像数 (${img_count}) 少于采样数 (${NUM_VIEWS}), 使用全部${NC}"
        NUM_VIEWS_ACTUAL=$img_count
    else
        NUM_VIEWS_ACTUAL=$NUM_VIEWS
    fi
    
    # 采样索引 (输出十进制整数)
    echo "  采样策略: ${SAMPLING_STRATEGY}"
    mapfile -t selected_indices < <(sample_indices_uniform "$img_count" "$NUM_VIEWS_ACTUAL")
    echo "  选中索引(十进制): ${selected_indices[*]}"
    
    # 创建目标目录
    mkdir -p "${dst_dir}/images" "${dst_dir}/sparse/0" "${dst_dir}/masks"
    
    # 复制 COLMAP 结果
    if [ -d "${src_dir}/sparse/0" ]; then
        cp "${src_dir}/sparse/0"/* "${dst_dir}/sparse/0/" 2>/dev/null
        echo "    ✓ COLMAP 重建结果"
    fi
    
    # 复制匹配先验
    if [ -f "${src_dir}/match_data.npy" ]; then
        cp "${src_dir}/match_data.npy" "${dst_dir}/"
        echo "    ✓ match_data.npy"
    fi
    
    # ✅ 修复: 复制图像 (使用十进制索引 + 大小写扩展名)
    echo "  复制 ${#selected_indices[@]} 张训练图像..."
    copied_count=0
    for idx in "${selected_indices[@]}"; do
        img_file=$(find_image_file "$img_src" "$idx")
        if [ -n "$img_file" ] && [ -f "$img_file" ]; then
            cp "$img_file" "${dst_dir}/images/"
            echo "    ✓ $(basename $img_file)"
            ((copied_count++))
        else
            # 调试: 列出目录内容帮助排查
            echo -e "${YELLOW}    ⚠ 未找到索引 ${idx} 的图像${NC}"
            echo "      目录示例: $(ls "$img_src" | head -3)"
        fi
    done
    echo "    已复制: ${copied_count}/${#selected_indices[@]}"
    
    # 生成配置
    cat > "${dst_dir}/fewshot_config.txt" << EOF
# Few-shot subset configuration
scene: ${scene}
total_images: ${img_count}
train_views: ${NUM_VIEWS_ACTUAL}
sampling: ${SAMPLING_STRATEGY}
indices: ${selected_indices[*]}
generated: $(date)
EOF
    echo "    ✓ fewshot_config.txt"
    
    echo -e "${GREEN}✓ 完成: ${scene}${NC}"
    ((success_count++))
done

# ============================================================================
# 汇总 (确保语法完整)
# ============================================================================

echo ""
echo "============================================================"
echo -e "${BLUE}  创建完成统计${NC}"
echo "============================================================"
echo "  成功: ${GREEN}${success_count}${NC} | 错误: ${RED}${error_count}${NC}"
echo "  输出: ${FEWSHOT_BASE}/"
echo "============================================================"

if [ "$success_count" -gt 0 ]; then
    echo ""
    echo "=== 使用示例 ==="
    echo "python train.py -s ${FEWSHOT_BASE}/fern -m output/fern_fewshot --iterations 30000 --eval"
fi

echo -e "${GREEN}✓ 脚本执行完成！${NC}"
echo "  结束时间：$(date '+%Y-%m-%d %H:%M:%S')"
# ✅ 确保脚本以正常退出结束
exit 0
