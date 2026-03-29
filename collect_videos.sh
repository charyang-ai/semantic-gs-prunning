#!/bin/bash
# ============================================================================
# SCGaussian 视频结果收集脚本 (路径修复版)
# 功能：根据实际视频路径结构收集所有场景视频
# ============================================================================

# 配置
OUT_BASE="../output_SCG/LLFF"
COLLECT_DIR="./collected_videos"
scenes=("fern" "flower" "fortress" "horns" "leaves" "orchids" "room" "trex")

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "============================================================"
echo -e "${BLUE}  SCGaussian 视频结果收集脚本 (路径修复版)${NC}"
echo "============================================================"
echo "  开始时间：$(date '+%Y-%m-%d %H:%M:%S')"
echo "  输出目录：${OUT_BASE}"
echo "  收集目录：${COLLECT_DIR}"
echo "  场景数量：${#scenes[@]}"
echo "============================================================"
echo ""

# 创建收集目录
mkdir -p "${COLLECT_DIR}"

# 统计
total_scenes=${#scenes[@]}
found_count=0
missing_count=0
copied_count=0

# 存储找到的视频文件列表
declare -a video_files

echo "=== 扫描场景视频文件 ==="
for scene in "${scenes[@]}"; do
    output_dir="${OUT_BASE}/${scene}"
    
    # ✅ 修复：实际视频路径结构
    video_dir="${output_dir}/video/ours_30000"
    
    printf "  %-10s : " "$scene"
    
    # 检查视频目录是否存在
    if [ ! -d "$video_dir" ]; then
        echo -e "${RED}✗ 视频目录不存在${NC}"
        echo "     期望路径：$video_dir"
        ((missing_count++))
        continue
    fi
    
    # 查找渲染视频文件（优先 render_video.mp4）
    video_file=""
    if [ -f "${video_dir}/render_video.mp4" ]; then
        video_file="${video_dir}/render_video.mp4"
    elif [ -f "${video_dir}/trajectory.mp4" ]; then
        video_file="${video_dir}/trajectory.mp4"
    else
        # 查找任意 mp4 文件
        video_file=$(find "$video_dir" -maxdepth 1 -type f -name "*.mp4" 2>/dev/null | head -n1)
    fi
    
    if [ -n "$video_file" ] && [ -f "$video_file" ]; then
        file_size=$(du -h "$video_file" | cut -f1)
        echo -e "${GREEN}✓ 找到视频${NC} ($(basename $video_file), ${file_size})"
        video_files+=("$scene:$video_file")
        ((found_count++))
    else
        echo -e "${YELLOW}⚠ 未找到视频文件${NC}"
        echo "     目录内容：$(ls -la $video_dir 2>/dev/null | head -5)"
        ((missing_count++))
    fi
done

echo ""
echo "=== 复制视频到收集目录 ==="

# 复制视频文件
for item in "${video_files[@]}"; do
    scene="${item%%:*}"
    video_file="${item#*:}"
    
    # 生成目标文件名
    file_ext="${video_file##*.}"
    target_name="${scene}_trajectory.${file_ext}"
    target_path="${COLLECT_DIR}/${target_name}"
    
    printf "  %-10s : " "$scene"
    
    # 复制文件（使用硬链接加速，如果失败则复制）
    if ln "$video_file" "$target_path" 2>/dev/null; then
        echo -e "${GREEN}✓ 创建硬链接${NC}"
        ((copied_count++))
    elif cp "$video_file" "$target_path" 2>/dev/null; then
        echo -e "${GREEN}✓ 复制完成${NC}"
        ((copied_count++))
    else
        echo -e "${RED}✗ 复制失败${NC}"
    fi
done

echo ""
echo "=== 生成视频索引文件 ==="

# 创建索引文件
index_file="${COLLECT_DIR}/video_index.txt"
cat > "$index_file" << EOF
============================================================
SCGaussian LLFF 视频结果索引
============================================================
生成时间：$(date '+%Y-%m-%d %H:%M:%S')
迭代次数：30000
场景总数：${total_scenes}
找到视频：${found_count}
成功收集：${copied_count}
缺失视频：${missing_count}
============================================================

视频列表:
------------------------------------------------------------
EOF

# 添加视频列表
for scene in "${scenes[@]}"; do
    target_path="${COLLECT_DIR}/${scene}_trajectory.mp4"
    if [ -f "$target_path" ]; then
        file_size=$(du -h "$target_path" | cut -f1)
        echo "  [✓] ${scene}: ${scene}_trajectory.mp4 (${file_size})" >> "$index_file"
    else
        echo "  [✗] ${scene}: 视频缺失" >> "$index_file"
    fi
done

cat >> "$index_file" << EOF

------------------------------------------------------------
使用说明:
  1. 播放单个视频:
     mpv ${COLLECT_DIR}/fern_trajectory.mp4
     ffplay ${COLLECT_DIR}/fern_trajectory.mp4
  
  2. 批量播放（按顺序）:
     for f in ${COLLECT_DIR}/*.mp4; do mpv "\$f"; done
  
  3. 合并所有视频（需要 ffmpeg）:
     ffmpeg -f concat -safe 0 -i <(for f in ${COLLECT_DIR}/*.mp4; do echo "file '\$f'"; done) -c copy all_scenes.mp4

============================================================
EOF

echo -e "${GREEN}  索引文件已生成：${index_file}${NC}"

echo ""
echo "=== 生成 HTML 预览页面 ==="

# 创建 HTML 预览页面
html_file="${COLLECT_DIR}/video_gallery.html"
cat > "$html_file" << HTMLHEADER
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SCGaussian LLFF 视频结果</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        h1 { color: #333; text-align: center; }
        .info { background: #fff; padding: 15px; border-radius: 8px; margin-bottom: 20px; }
        .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(400px, 1fr)); gap: 20px; }
        .card { background: #fff; border-radius: 8px; overflow: hidden; box-shadow: 0 2px 8px rgba(0,0,0,0.1); }
        .card h3 { margin: 0; padding: 15px; background: #4a90d9; color: white; }
        .card video { width: 100%; display: block; }
        .card .info { margin: 0; padding: 10px 15px; border-radius: 0; }
        .missing { background: #ffebee; color: #c62828; padding: 15px; text-align: center; }
    </style>
</head>
<body>
    <h1>🎬 SCGaussian LLFF 视频结果</h1>
    
    <div class="info">
        <strong>生成时间:</strong> $(date '+%Y-%m-%d %H:%M:%S')<br>
        <strong>迭代次数:</strong> 30000<br>
        <strong>场景总数:</strong> ${total_scenes} | 
        <strong>找到视频:</strong> ${found_count} | 
        <strong>成功收集:</strong> ${copied_count}
    </div>
    
    <div class="grid">
HTMLHEADER

# 添加视频卡片
for scene in "${scenes[@]}"; do
    target_path="${COLLECT_DIR}/${scene}_trajectory.mp4"
    if [ -f "$target_path" ]; then
        file_size=$(du -h "$target_path" | cut -f1)
        cat >> "$html_file" << EOF
        <div class="card">
            <h3>📍 ${scene}</h3>
            <video controls>
                <source src="${scene}_trajectory.mp4" type="video/mp4">
                您的浏览器不支持视频播放
            </video>
            <div class="info">
                <strong>文件大小:</strong> ${file_size}<br>
                <strong>文件名:</strong> ${scene}_trajectory.mp4
            </div>
        </div>
EOF
    else
        cat >> "$html_file" << EOF
        <div class="card">
            <div class="missing">
                <h3>📍 ${scene}</h3>
                <p>⚠ 视频文件缺失</p>
            </div>
        </div>
EOF
    fi
done

# 完成 HTML
cat >> "$html_file" << 'HTMLFOOTER'
    </div>
    
    <footer style="text-align: center; margin-top: 30px; color: #666;">
        <p>SCGaussian Video Gallery | Generated by collect_videos.sh</p>
    </footer>
</body>
</html>
HTMLFOOTER

echo -e "${GREEN}  HTML 预览页面已生成：${html_file}${NC}"

echo ""
echo "============================================================"
echo -e "${BLUE}  收集完成统计${NC}"
echo "============================================================"
echo "  场景总数：${total_scenes}"
echo -e "  找到视频：${GREEN}${found_count}${NC}"
echo -e "  成功收集：${GREEN}${copied_count}${NC}"
echo -e "  缺失视频：${RED}${missing_count}${NC}"
echo ""
echo "  收集目录：${COLLECT_DIR}/"
echo "  索引文件：${index_file}"
echo "  HTML 预览：${html_file}"
echo "============================================================"
echo "  结束时间：$(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"

# 如果 ffmpeg 可用，提供合并选项
if command -v ffmpeg &> /dev/null && [ $copied_count -gt 1 ]; then
    echo ""
    echo "=== 可选：合并所有视频为单个文件 ==="
    echo "提示：运行以下命令合并所有视频"
    echo "  cd ${COLLECT_DIR} && ffmpeg -f concat -safe 0 -i <(for f in *.mp4; do echo \"file '\$f'\"; done) -c copy all_scenes.mp4"
fi

echo ""
echo -e "${GREEN}✓ 脚本执行完成！${NC}"
