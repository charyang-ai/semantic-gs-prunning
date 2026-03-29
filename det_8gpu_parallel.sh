#!/bin/bash
# ============================================================================
# SCGaussian 智能增量执行脚本（带进度条版本）
# 功能：Train/Render 增量执行，Metrics 强制重算，实时进度监控
# ============================================================================

# Base paths
DATA_BASE="../data/LLFF"
OUT_BASE="../output_SCG/LLFF"

# List of scenes in the order corresponding to GPU indices (0-7)
scenes=("fern" "flower" "fortress" "horns" "leaves" "orchids" "room" "trex")
total_scenes=${#scenes[@]}

# Configuration
ITERATIONS=30000
DOWNSAMPLE_FACTOR=8

# Progress tracking
declare -A scene_status  # 记录每个场景的状态
declare -A scene_pid     # 记录每个场景的进程ID
declare -A scene_start   # 记录每个场景的开始时间

# ============================================================================
# 状态检测函数
# ============================================================================

check_train_completed() {
    local output_dir=$1
    if [ -f "${output_dir}/point_cloud/iteration_${ITERATIONS}/point_cloud.ply" ] && \
       [ -f "${output_dir}/cfg_args" ] && \
       [ -f "${output_dir}/chkpnt${ITERATIONS}.pth" ]; then
        return 0
    else
        return 1
    fi
}

check_render_completed() {
    local output_dir=$1
    local render_dir="${output_dir}/test/ours_${ITERATIONS}/renders"
    if [ -d "$render_dir" ] && [ "$(ls -A $render_dir/*.png 2>/dev/null)" ]; then
        return 0
    else
        return 1
    fi
}

# ============================================================================
# 进度条显示函数
# ============================================================================

print_progress_bar() {
    local completed=$1
    local total=$2
    local width=50
    local percentage=$((completed * 100 / total))
    local filled=$((completed * width / total))
    local empty=$((width - filled))
    
    # 生成进度条
    local bar="["
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    bar+="]"
    
    # 打印进度条（覆盖当前行）
    printf "\r\033[K  Progress: %s %3d%% (%d/%d scenes completed)" "$bar" "$percentage" "$completed" "$total"
}

print_scene_status() {
    echo ""
    echo "  ┌─────────────────────────────────────────────────────────────┐"
    echo "  │ Scene Status Monitor                                        │"
    echo "  ├─────────────────────────────────────────────────────────────┤"
    
    for idx in "${!scenes[@]}"; do
        scene="${scenes[$idx]}"
        output_dir="${OUT_BASE}/${scene}"
        status="${scene_status[$scene]:-pending}"
        
        # 确定状态图标
        case $status in
            "completed") icon="✓"; color="\033[32m" ;;  # 绿色
            "training")  icon="🔄"; color="\033[34m" ;;  # 蓝色
            "rendering") icon="🎬"; color="\033[33m" ;;  # 黄色
            "metrics")   icon="📊"; color="\033[35m" ;;  # 紫色
            "failed")    icon="✗"; color="\033[31m" ;;  # 红色
            *)           icon="⏳"; color="\033[90m" ;;  # 灰色
        esac
        
        # 检查实际完成状态（覆盖记录状态）
        if [ -f "${output_dir}/results.json" ]; then
            status="completed"
            icon="✓"
            color="\033[32m"
        elif [ -d "${output_dir}/test/ours_${ITERATIONS}/renders" ]; then
            status="metrics"
            icon="📊"
            color="\033[35m"
        elif [ -f "${output_dir}/point_cloud/iteration_${ITERATIONS}/point_cloud.ply" ]; then
            status="rendering"
            icon="🎬"
            color="\033[33m"
        fi
        
        scene_status[$scene]=$status
        
        # 打印场景状态
        printf "  │ %s GPU%-1d %-10s %b%s\033[0m\n" "$icon" "$idx" "$scene" "$color" "$status"
    done
    
    echo "  └─────────────────────────────────────────────────────────────┘"
}

update_progress() {
    local completed=0
    for scene in "${scenes[@]}"; do
        output_dir="${OUT_BASE}/${scene}"
        if [ -f "${output_dir}/results.json" ]; then
            ((completed++))
        fi
    done
    
    print_progress_bar $completed $total_scenes
    echo ""
    print_scene_status
}

cleanup_progress() {
    # 清除进度显示，准备最终输出
    printf "\r\033[K"
}

# ============================================================================
# 单场景处理函数
# ============================================================================

process_scene() {
    local gpu=$1
    local scene=$2
    local log_file="logs/scene_${scene}_gpu${gpu}.log"
    
    echo "=== Starting scene $scene on GPU $gpu ===" | tee "$log_file"
    echo "Timestamp: $(date)" | tee -a "$log_file"
    
    input_dir="${DATA_BASE}/${scene}"
    output_dir="${OUT_BASE}/${scene}"
    
    if [ ! -d "$input_dir" ]; then
        echo "ERROR: Input directory $input_dir does not exist. Skipping." | tee -a "$log_file"
        scene_status[$scene]="failed"
        return 1
    fi
    
    mkdir -p "$output_dir"
    
    # 状态检测
    train_done=false
    render_done=false
    
    if check_train_completed "$output_dir"; then
        echo "✓ Train completed (iteration ${ITERATIONS})" | tee -a "$log_file"
        train_done=true
    else
        echo "✗ Train NOT completed, will execute..." | tee -a "$log_file"
    fi
    
    if check_render_completed "$output_dir"; then
        echo "✓ Render completed" | tee -a "$log_file"
        render_done=true
    else
        echo "✗ Render NOT completed, will execute..." | tee -a "$log_file"
    fi
    
    echo "⚠ Metrics will be recomputed (forced)" | tee -a "$log_file"
    echo "" | tee -a "$log_file"
    
    # ========== Step 1: Train ==========
    if [ "$train_done" = false ]; then
        scene_status[$scene]="training"
        echo "========================================" | tee -a "$log_file"
        echo "Step 1/3: Training $scene on GPU $gpu ..." | tee -a "$log_file"
        echo "========================================" | tee -a "$log_file"
        start_time=$(date +%s)
        
        CUDA_VISIBLE_DEVICES=$gpu python train.py -s "$input_dir" -m "$output_dir" \
            --iterations $ITERATIONS -r $DOWNSAMPLE_FACTOR --eval >> "$log_file" 2>&1
        
        train_status=$?
        end_time=$(date +%s)
        train_duration=$((end_time - start_time))
        
        if [ $train_status -ne 0 ]; then
            echo "ERROR: Training failed for $scene on GPU $gpu (duration: ${train_duration}s)" | tee -a "$log_file"
            scene_status[$scene]="failed"
            return 1
        fi
        
        echo "✓ Training completed successfully (duration: ${train_duration}s)" | tee -a "$log_file"
        echo "" | tee -a "$log_file"
    else
        echo "⊘ Step 1/3: Training skipped (already completed)" | tee -a "$log_file"
        echo "" | tee -a "$log_file"
    fi
    
    # ========== Step 2: Render ==========
    if [ "$render_done" = false ]; then
        scene_status[$scene]="rendering"
        echo "========================================" | tee -a "$log_file"
        echo "Step 2/3: Rendering $scene on GPU $gpu ..." | tee -a "$log_file"
        echo "========================================" | tee -a "$log_file"
        start_time=$(date +%s)
        
        CUDA_VISIBLE_DEVICES=$gpu python render.py -m "$output_dir" >> "$log_file" 2>&1
        
        render_status=$?
        end_time=$(date +%s)
        render_duration=$((end_time - start_time))
        
        if [ $render_status -ne 0 ]; then
            echo "ERROR: Rendering failed for $scene on GPU $gpu (duration: ${render_duration}s)" | tee -a "$log_file"
            scene_status[$scene]="failed"
            return 1
        fi
        
        echo "✓ Rendering completed successfully (duration: ${render_duration}s)" | tee -a "$log_file"
        echo "" | tee -a "$log_file"
    else
        echo "⊘ Step 2/3: Rendering skipped (already completed)" | tee -a "$log_file"
        echo "" | tee -a "$log_file"
    fi
    
    # ========== Step 3: Render Video (可选) ==========
    video_dir="${output_dir}/test/ours_${ITERATIONS}/video"
    if [ ! -d "$video_dir" ] || [ ! "$(ls -A $video_dir/*.mp4 2>/dev/null)" ]; then
        echo "========================================" | tee -a "$log_file"
        echo "Step 2.5/3: Rendering video for $scene (optional) ..." | tee -a "$log_file"
        echo "========================================" | tee -a "$log_file"
        
        CUDA_VISIBLE_DEVICES=$gpu python render_video.py -m "$output_dir" >> "$log_file" 2>&1
        
        if [ $? -ne 0 ]; then
            echo "⚠ WARNING: Video rendering failed for $scene (non-critical)" | tee -a "$log_file"
        else
            echo "✓ Video rendering completed" | tee -a "$log_file"
        fi
        echo "" | tee -a "$log_file"
    fi
    
    # ========== Step 4: Metrics (强制重算) ==========
    scene_status[$scene]="metrics"
    echo "========================================" | tee -a "$log_file"
    echo "Step 3/3: Computing metrics for $scene (FORCED) ..." | tee -a "$log_file"
    echo "========================================" | tee -a "$log_file"
    start_time=$(date +%s)
    
    rm -f "${output_dir}/results.json" "${output_dir}/per_view.json"
    
    CUDA_VISIBLE_DEVICES=$gpu python metrics.py -m "$output_dir" >> "$log_file" 2>&1
    
    metrics_status=$?
    end_time=$(date +%s)
    metrics_duration=$((end_time - start_time))
    
    if [ $metrics_status -ne 0 ]; then
        echo "ERROR: Metrics computation failed for $scene (duration: ${metrics_duration}s)" | tee -a "$log_file"
        scene_status[$scene]="failed"
        return 1
    fi
    
    if [ -f "${output_dir}/results.json" ]; then
        echo "✓ Metrics completed successfully (duration: ${metrics_duration}s)" | tee -a "$log_file"
    else
        echo "⚠ Metrics finished but output files missing!" | tee -a "$log_file"
        scene_status[$scene]="failed"
        return 1
    fi
    echo "" | tee -a "$log_file"
    
    # ========== 完成 ==========
    scene_status[$scene]="completed"
    echo "========================================" | tee -a "$log_file"
    echo "✓ Finished $scene on GPU $gpu successfully." | tee -a "$log_file"
    echo "========================================" | tee -a "$log_file"
    return 0
}

# ============================================================================
# 进度监控进程
# ============================================================================

monitor_progress() {
    while true; do
        # 检查是否所有场景都完成
        local all_done=true
        for scene in "${scenes[@]}"; do
            output_dir="${OUT_BASE}/${scene}"
            if [ ! -f "${output_dir}/results.json" ]; then
                all_done=false
                break
            fi
        done
        
        # 更新进度显示
        clear
        echo "============================================================"
        echo "  SCGaussian 智能执行脚本 - 实时进度监控"
        echo "============================================================"
        echo "  Start time: $script_start_time"
        echo "  Current time: $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
        update_progress
        
        if [ "$all_done" = true ]; then
            break
        fi
        
        # 每5秒更新一次
        sleep 5
    done
}

# ============================================================================
# 主执行流程
# ============================================================================

# 记录开始时间
script_start_time=$(date '+%Y-%m-%d %H:%M:%S')
script_start_epoch=$(date +%s)

# 清屏并显示初始信息
clear
echo "============================================================"
echo "  SCGaussian 智能增量执行脚本 (带进度条版本)"
echo "============================================================"
echo "  Start time: $script_start_time"
echo "  GPU count: 8"
echo "  Scenes: ${scenes[*]}"
echo "  Iterations: ${ITERATIONS}"
echo "  Downsample factor: ${DOWNSAMPLE_FACTOR}"
echo "============================================================"
echo ""

# 预检查所有场景状态
echo "=== Pre-check: Scene Status ==="
for idx in "${!scenes[@]}"; do
    scene="${scenes[$idx]}"
    output_dir="${OUT_BASE}/${scene}"
    
    train_status="✗"
    render_status="✗"
    
    if [ -d "$output_dir" ]; then
        check_train_completed "$output_dir" && train_status="✓"
        check_render_completed "$output_dir" && render_status="✓"
    fi
    
    printf "  %-10s | Train: %s | Render: %s | Metrics: FORCED\n" \
        "$scene" "$train_status" "$render_status"
done
echo ""
echo "Press Ctrl+C to view logs (logs are saved to logs/scene_*.log files)"
echo "============================================================"
echo ""

# 启动进度监控进程（后台）
monitor_progress &
monitor_pid=$!

# 启动所有场景处理进程
echo "=== Launching parallel tasks ==="
for idx in "${!scenes[@]}"; do
    gpu=$idx
    scene="${scenes[$idx]}"
    scene_start[$scene]=$(date +%s)
    process_scene "$gpu" "$scene" &
    scene_pid[$scene]=$!
done

# 等待所有场景进程完成
wait

# 停止监控进程
kill $monitor_pid 2>/dev/null

# 清除进度显示，准备最终输出
clear

echo ""
echo "============================================================"
echo "✓ All scenes processed successfully."
echo "============================================================"
echo "  Start time: $script_start_time"
echo "  End time: $(date '+%Y-%m-%d %H:%M:%S')"
total_duration=$(( $(date +%s) - script_start_epoch ))
echo "  Total duration: ${total_duration}s ($((total_duration/60))m ${total_duration%60}s)"
echo "============================================================"
echo ""

# 最终状态汇总
echo "=== Final Status Summary ==="
for idx in "${!scenes[@]}"; do
    scene="${scenes[$idx]}"
    output_dir="${OUT_BASE}/${scene}"
    
    train_status="✗"
    render_status="✗"
    metrics_status="✗"
    
    check_train_completed "$output_dir" && train_status="✓"
    check_render_completed "$output_dir" && render_status="✓"
    [ -f "${output_dir}/results.json" ] && metrics_status="✓"
    
    printf "  %-10s | Train: %s | Render: %s | Metrics: %s\n" \
        "$scene" "$train_status" "$render_status" "$metrics_status"
done

# 汇总所有 results.json 到 CSV
echo ""
echo "=== Aggregating results to results.csv ==="
python3 << 'PYEOF'
import json, csv, os
scenes = ["fern","flower","fortress","horns","leaves","orchids","room","trex"]
base = "../output_SCG/LLFF"
output_csv = "results.csv"

with open(output_csv, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['scene','SSIM','PSNR','LPIPS','AVG'])
    for scene in scenes:
        try:
            results_file = os.path.join(base, scene, "results.json")
            if os.path.exists(results_file):
                with open(results_file) as jf:
                    data = json.load(jf)
                    for method, m in data.items():
                        writer.writerow([scene, m['SSIM'], m['PSNR'], m['LPIPS'], m['AVG']])
                        print(f"  ✓ {scene}: SSIM={m['SSIM']:.4f}, PSNR={m['PSNR']:.2f}, LPIPS={m['LPIPS']:.4f}, AVG={m['AVG']:.4f}")
            else:
                print(f"  ✗ {scene}: results.json not found")
        except Exception as e:
            print(f"  ✗ {scene}: {e}")

print(f"\nResults saved to {output_csv}")
PYEOF

echo ""
echo "============================================================"
echo "✓ Script completed successfully."
echo "============================================================"
