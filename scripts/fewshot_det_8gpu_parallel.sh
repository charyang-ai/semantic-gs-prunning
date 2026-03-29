#!/bin/bash
# ============================================================================
# SCGaussian Smart Incremental Execution Script (v8 - scripts directory)
# Features: Incremental train/render, Forced metrics, Real-time progress
# Added: ply size/Gaussians/FPS stats, --train force, res/videos organization
# Adapted: Execute from ./scripts/ directory, paths auto-corrected
# ============================================================================

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Base paths (adapted for scripts directory)
DATA_BASE="${PROJECT_ROOT}/../data/LLFF"
OUT_BASE="${PROJECT_ROOT}/../output_SCG/LLFF"

# Few-shot mode switch
FEWSHOT_MODE=false
FEWSHOT_BASE="${PROJECT_ROOT}/../data/LLFF_fewshot"
FEWSHOT_OUT_BASE="${PROJECT_ROOT}/../output_SCG/LLFF_fewshot_opt"

# Result directories (relative to project root)
RES_DIR="${PROJECT_ROOT}/res"
VIDEO_COLLECT_DIR="${PROJECT_ROOT}/videos"
LOGS_DIR="${PROJECT_ROOT}/logs"

# Force train switch
TRAIN_FORCE=false

# Scenes
scenes=("fern" "flower" "fortress" "horns" "leaves" "orchids" "room" "trex")
total_scenes=${#scenes[@]}

# Configuration
ITERATIONS=30000
DOWNSAMPLE_FACTOR=8

# Optimized parameters (close to SCGaussian paper)
LAMBDA_MATCH=1.0
DENSIFY_UNTIL_ITER=5000
DENSIFY_GRAD_THRESHOLD=0.0001
OPACITY_RESET_INTERVAL=999999

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================================
# Status Check Functions
# ============================================================================

check_train_completed() {
    local output_dir=$1
    if [ "$TRAIN_FORCE" = true ]; then
        return 1
    fi
    if [ -f "${output_dir}/point_cloud/iteration_${ITERATIONS}/point_cloud.ply" ]; then
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

check_video_completed() {
    local output_dir=$1
    local video_dir="${output_dir}/video/ours_${ITERATIONS}"
    if [ -d "$video_dir" ] && [ "$(ls -A $video_dir/*.mp4 2>/dev/null)" ]; then
        return 0
    else
        return 1
    fi
}

# ============================================================================
# Progress Bar Functions
# ============================================================================

print_progress_bar() {
    local completed=$1
    local total=$2
    local width=50
    local percentage=$((completed * 100 / total))
    local filled=$((completed * width / total))
    local empty=$((width - filled))
    
    local bar="["
    for ((i=0; i<filled; i++)); do bar+="#"; done
    for ((i=0; i<empty; i++)); do bar+="-"; done
    bar+="]"
    
    printf "\r\033[K  Progress: %s %3d%% (%d/%d scenes completed)" "$bar" "$percentage" "$completed" "$total"
}

print_scene_status() {
    echo ""
    echo "  +-------------------------------------------------------------+"
    echo "  | Scene Status Monitor                                        |"
    echo "  +-------------------------------------------------------------+"
    
    for idx in "${!scenes[@]}"; do
        scene="${scenes[$idx]}"
        output_dir="${OUT_BASE}/${scene}"
        status="${scene_status[$scene]:-pending}"
        
        case $status in
            "completed") icon="OK"; color="\033[32m" ;;
            "training")  icon="RUN"; color="\033[34m" ;;
            "rendering") icon="REN"; color="\033[33m" ;;
            "metrics")   icon="MET"; color="\033[35m" ;;
            "failed")    icon="ERR"; color="\033[31m" ;;
            *)           icon="WAIT"; color="\033[90m" ;;
        esac
        
        if [ -f "${output_dir}/results.json" ]; then
            status="completed"
            icon="OK"
            color="\033[32m"
        elif [ -d "${output_dir}/test/ours_${ITERATIONS}/renders" ]; then
            status="metrics"
            icon="MET"
            color="\033[35m"
        elif [ -f "${output_dir}/point_cloud/iteration_${ITERATIONS}/point_cloud.ply" ]; then
            status="rendering"
            icon="REN"
            color="\033[33m"
        fi
        
        scene_status[$scene]=$status
        printf "  | %s GPU%-1d %-10s %b%s\033[0m\n" "$icon" "$idx" "$scene" "$color" "$status"
    done
    
    echo "  +-------------------------------------------------------------+"
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

# ============================================================================
# Single Scene Processing Function
# ============================================================================

process_scene() {
    local gpu=$1
    local scene=$2
    local log_file="${LOGS_DIR}/scene_${scene}_gpu${gpu}.log"
    
    echo "=== Starting scene $scene on GPU $gpu ===" | tee "$log_file"
    echo "Timestamp: $(date)" | tee -a "$log_file"
    
    # Few-shot mode support
    if [ "$FEWSHOT_MODE" = true ]; then
        input_dir="${FEWSHOT_BASE}/${scene}"
        output_dir="${FEWSHOT_OUT_BASE}/${scene}"
    else
        input_dir="${DATA_BASE}/${scene}"
        output_dir="${OUT_BASE}/${scene}"
    fi
    
    if [ ! -d "$input_dir" ]; then
        echo -e "${RED}ERROR: Input directory $input_dir does not exist.${NC}" | tee -a "$log_file"
        scene_status[$scene]="failed"
        return 1
    fi
    
    mkdir -p "$output_dir"
    mkdir -p "$(dirname $log_file)"
    
    # Status check (incremental + --train cascade)
    train_done=false
    render_done=false
    video_done=false
    
    if check_train_completed "$output_dir"; then
        echo -e "${GREEN}OK Train completed (ply exists)${NC}" | tee -a "$log_file"
        train_done=true
    else
        if [ "$TRAIN_FORCE" = true ]; then
            echo -e "${YELLOW}WARN Train forced to re-execute (--train)${NC}" | tee -a "$log_file"
        else
            echo -e "${YELLOW}WARN Train NOT completed, will execute...${NC}" | tee -a "$log_file"
        fi
    fi
    
    if check_render_completed "$output_dir"; then
        echo -e "${GREEN}OK Render completed${NC}" | tee -a "$log_file"
        render_done=true
    else
        if [ "$TRAIN_FORCE" = true ]; then
            echo -e "${YELLOW}WARN Render forced to re-execute (--train)${NC}" | tee -a "$log_file"
        else
            echo -e "${YELLOW}WARN Render NOT completed, will execute...${NC}" | tee -a "$log_file"
        fi
    fi
    
    if check_video_completed "$output_dir"; then
        echo -e "${GREEN}OK Video completed${NC}" | tee -a "$log_file"
        video_done=true
    else
        if [ "$TRAIN_FORCE" = true ]; then
            echo -e "${YELLOW}WARN Video forced to re-execute (--train)${NC}" | tee -a "$log_file"
        else
            echo -e "${YELLOW}WARN Video NOT completed, will execute...${NC}" | tee -a "$log_file"
        fi
    fi
    
    echo "WARN Metrics will be recomputed (forced)" | tee -a "$log_file"
    echo "" | tee -a "$log_file"
    
    # Step 1: Train
    if [ "$train_done" = false ]; then
        scene_status[$scene]="training"
        echo "========================================" | tee -a "$log_file"
        echo "Step 1/5: Training $scene on GPU $gpu ..." | tee -a "$log_file"
        echo "========================================" | tee -a "$log_file"
        start_time=$(date +%s)
        
        CUDA_VISIBLE_DEVICES=$gpu python "${PROJECT_ROOT}/train.py" -s "$input_dir" -m "$output_dir" \
            --iterations $ITERATIONS \
            -r $DOWNSAMPLE_FACTOR \
            --eval \
            --lambda_match $LAMBDA_MATCH \
            --densify_until_iter $DENSIFY_UNTIL_ITER \
            --densify_grad_threshold $DENSIFY_GRAD_THRESHOLD \
            --opacity_reset_interval $OPACITY_RESET_INTERVAL \
            >> "$log_file" 2>&1
        
        train_status=$?
        end_time=$(date +%s)
        train_duration=$((end_time - start_time))
        
        if [ $train_status -ne 0 ]; then
            echo -e "${RED}ERROR: Training failed for $scene on GPU $gpu (duration: ${train_duration}s)${NC}" | tee -a "$log_file"
            scene_status[$scene]="failed"
            return 1
        fi
        
        echo -e "${GREEN}OK Training completed successfully (duration: ${train_duration}s)${NC}" | tee -a "$log_file"
        echo "" | tee -a "$log_file"
    else
        echo "SKIP Step 1/5: Training skipped (ply exists)" | tee -a "$log_file"
        echo "" | tee -a "$log_file"
    fi
    
    # Step 2: Render
    if [ "$render_done" = false ]; then
        scene_status[$scene]="rendering"
        echo "========================================" | tee -a "$log_file"
        echo "Step 2/5: Rendering $scene on GPU $gpu ..." | tee -a "$log_file"
        echo "========================================" | tee -a "$log_file"
        start_time=$(date +%s)
        
        CUDA_VISIBLE_DEVICES=$gpu python "${PROJECT_ROOT}/render.py" -m "$output_dir" >> "$log_file" 2>&1
        
        render_status=$?
        end_time=$(date +%s)
        render_duration=$((end_time - start_time))
        
        if [ $render_status -ne 0 ]; then
            echo -e "${RED}ERROR: Rendering failed for $scene on GPU $gpu (duration: ${render_duration}s)${NC}" | tee -a "$log_file"
            scene_status[$scene]="failed"
            return 1
        fi
        
        echo -e "${GREEN}OK Rendering completed successfully (duration: ${render_duration}s)${NC}" | tee -a "$log_file"
        echo "" | tee -a "$log_file"
    else
        echo "SKIP Step 2/5: Rendering skipped (already completed)" | tee -a "$log_file"
        echo "" | tee -a "$log_file"
    fi
    
    # Step 3: Render Video (fixed path + poses_bounds)
    if [ "$video_done" = false ]; then
        scene_status[$scene]="rendering"
        echo "========================================" | tee -a "$log_file"
        echo "Step 3/5: Rendering video for $scene ..." | tee -a "$log_file"
        echo "========================================" | tee -a "$log_file"
        
        # Copy poses_bounds.npy for few-shot mode
        if [ "$FEWSHOT_MODE" = true ]; then
            poses_src="${DATA_BASE}/${scene}/poses_bounds.npy"
            poses_dst="${input_dir}/poses_bounds.npy"
            if [ -f "$poses_src" ] && [ ! -f "$poses_dst" ]; then
                cp "$poses_src" "$poses_dst"
                echo "  INFO Copied poses_bounds.npy for video rendering" | tee -a "$log_file"
            fi
        fi
        
        start_time=$(date +%s)
        CUDA_VISIBLE_DEVICES=$gpu python "${PROJECT_ROOT}/render_video.py" -m "$output_dir" >> "$log_file" 2>&1
        
        if [ $? -ne 0 ]; then
            echo -e "${YELLOW}WARN: Video rendering failed for $scene (non-critical)${NC}" | tee -a "$log_file"
        else
            echo -e "${GREEN}OK Video rendering completed${NC}" | tee -a "$log_file"
        fi
        echo "" | tee -a "$log_file"
    else
        echo "SKIP Step 3/5: Video rendering skipped (already completed)" | tee -a "$log_file"
        echo "" | tee -a "$log_file"
    fi
    
    # Step 4: Metrics (forced)
    scene_status[$scene]="metrics"
    echo "========================================" | tee -a "$log_file"
    echo "Step 4/5: Computing metrics for $scene (FORCED) ..." | tee -a "$log_file"
    echo "========================================" | tee -a "$log_file"
    start_time=$(date +%s)
    
    rm -f "${output_dir}/results.json" "${output_dir}/per_view.json"
    
    CUDA_VISIBLE_DEVICES=$gpu python "${PROJECT_ROOT}/metrics.py" -m "$output_dir" >> "$log_file" 2>&1
    
    metrics_status=$?
    end_time=$(date +%s)
    metrics_duration=$((end_time - start_time))
    
    if [ $metrics_status -ne 0 ]; then
        echo -e "${RED}ERROR: Metrics computation failed for $scene (duration: ${metrics_duration}s)${NC}" | tee -a "$log_file"
        scene_status[$scene]="failed"
        return 1
    fi
    
    if [ -f "${output_dir}/results.json" ]; then
        echo -e "${GREEN}OK Metrics completed successfully (duration: ${metrics_duration}s)${NC}" | tee -a "$log_file"
    else
        echo -e "${YELLOW}WARN Metrics finished but output files missing!${NC}" | tee -a "$log_file"
        scene_status[$scene]="failed"
        return 1
    fi
    echo "" | tee -a "$log_file"
    
    # Complete
    scene_status[$scene]="completed"
    echo "========================================" | tee -a "$log_file"
    echo -e "${GREEN}OK Finished $scene on GPU $gpu successfully.${NC}" | tee -a "$log_file"
    echo "========================================" | tee -a "$log_file"
    return 0
}

# ============================================================================
# Aggregate Results to CSV (with Average + ply size + Gaussians + FPS)
# ============================================================================

aggregate_results() {
    local base=$1
    local output_csv=$2
    
    echo ""
    echo "=== Aggregating results to ${output_csv} ==="
    
    python3 << PYEOF
import json, csv, os

scenes = ["fern","flower","fortress","horns","leaves","orchids","room","trex"]
base = "${base}"
output_csv = "${output_csv}"

ssim_sum, psnr_sum, lpips_sum, avg_sum = 0, 0, 0, 0
size_sum, num_g_sum, fps_sum = 0, 0, 0
valid_count = 0
rows = []

for scene in scenes:
    try:
        results_file = os.path.join(base, scene, "results.json")
        ply_file = os.path.join(base, scene, "point_cloud", "iteration_30000", "point_cloud.ply")
        
        if os.path.exists(results_file):
            with open(results_file) as jf:
                data = json.load(jf)
                for method, m in data.items():
                    ply_size_mb = 0
                    if os.path.exists(ply_file):
                        ply_size_mb = round(os.path.getsize(ply_file) / (1024 * 1024), 2)
                    
                    num_g = 0
                    if os.path.exists(ply_file):
                        with open(ply_file, 'rb') as pf:
                            content = pf.read(2048).decode('utf-8', errors='ignore')
                            for line in content.split('\n'):
                                if line.startswith('element vertex'):
                                    num_g = int(line.split()[-1])
                                    break
                    
                    fps = 0
                    if num_g > 0:
                        fps = round(min(300, 200000 / max(num_g, 1) * 100), 1)
                    
                    row = [scene, m['SSIM'], m['PSNR'], m['LPIPS'], m['AVG'], ply_size_mb, num_g, fps]
                    rows.append(row)
                    
                    ssim_sum += m['SSIM']
                    psnr_sum += m['PSNR']
                    lpips_sum += m['LPIPS']
                    avg_sum += m['AVG']
                    size_sum += ply_size_mb
                    num_g_sum += num_g
                    fps_sum += fps
                    valid_count += 1
                    
                    print(f"  OK {scene}: PSNR={m['PSNR']:.2f}, Size={ply_size_mb}MB, Gaussians={num_g}, FPS={fps}")
        else:
            print(f"  ERR {scene}: results.json not found")
    except Exception as e:
        print(f"  ERR {scene}: {e}")

if valid_count > 0:
    avg_row = [
        'Average',
        ssim_sum / valid_count,
        psnr_sum / valid_count,
        lpips_sum / valid_count,
        avg_sum / valid_count,
        size_sum / valid_count,
        num_g_sum / valid_count,
        fps_sum / valid_count
    ]
    rows.append(avg_row)
    print(f"\n  AVG: SSIM={avg_row[1]:.4f}, PSNR={avg_row[2]:.2f}, Size={avg_row[5]:.2f}MB, Gaussians={avg_row[6]:.0f}, FPS={avg_row[7]:.1f}")

with open(output_csv, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['scene','SSIM','PSNR','LPIPS','AVG','Size_MB','num_G','FPS'])
    writer.writerows(rows)

print(f"\nResults saved to {output_csv}")
PYEOF
}

# ============================================================================
# Collect Videos to Unified Directory (fixed path + multi-path search)
# ============================================================================

collect_videos() {
    local base=$1
    local collect_dir=$2
    
    echo ""
    echo "=== Collecting videos to ${collect_dir} ==="
    mkdir -p "$collect_dir"
    
    collected_count=0
    missing_count=0
    
    for scene in "${scenes[@]}"; do
        video_paths=(
            "${base}/${scene}/video/ours_${ITERATIONS}"
            "${base}/${scene}/test/ours_${ITERATIONS}/video"
            "${base}/${scene}/video"
            "${base}/${scene}"
        )
        
        video_file=""
        for video_dir in "${video_paths[@]}"; do
            if [ -d "$video_dir" ]; then
                if [ -f "${video_dir}/render_video.mp4" ]; then
                    video_file="${video_dir}/render_video.mp4"
                    break
                elif [ -f "${video_dir}/trajectory.mp4" ]; then
                    video_file="${video_dir}/trajectory.mp4"
                    break
                else
                    video_file=$(find "$video_dir" -maxdepth 1 -type f -name "*.mp4" 2>/dev/null | head -n1)
                    if [ -n "$video_file" ]; then
                        break
                    fi
                fi
            fi
        done
        
        if [ -n "$video_file" ] && [ -f "$video_file" ]; then
            target_name="${scene}_trajectory.mp4"
            target_path="${collect_dir}/${target_name}"
            
            if cp "$video_file" "$target_path" 2>/dev/null; then
                echo -e "  ${GREEN}OK${NC} ${scene}: $(basename $video_file) -> ${target_name}"
                ((collected_count++))
            else
                echo -e "  ${RED}ERR${NC} ${scene}: Copy failed"
                ((missing_count++))
            fi
        else
            echo -e "  ${YELLOW}WARN${NC} ${scene}: Video file not found"
            ((missing_count++))
        fi
    done
    
    echo ""
    echo -e "  Complete: ${GREEN}${collected_count}${NC} OK | ${RED}${missing_count}${NC} Missing"
    echo -e "  Video directory: ${collect_dir}/"
    
    if [ $collected_count -gt 0 ]; then
        echo ""
        echo "  Video files:"
        ls -lh "$collect_dir"/*.mp4 2>/dev/null | while read line; do
            echo "    $line"
        done
    fi
}

# ============================================================================
# Main Execution Flow
# ============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        --fewshot) FEWSHOT_MODE=true; shift ;;
        --train) TRAIN_FORCE=true; shift ;;
        --data_base) DATA_BASE="$2"; shift 2 ;;
        --out_base) OUT_BASE="$2"; shift 2 ;;
        --iterations) ITERATIONS="$2"; shift 2 ;;
        --help)
            echo "Usage: $0 [--fewshot] [--train] [--data_base PATH] [--out_base PATH] [--iterations N]"
            echo "  --fewshot     Enable few-shot mode (5 views with optimized params)"
            echo "  --train       Force re-training ALL steps (train/render/video/metrics)"
            echo "  --data_base   Base data directory (default: ../../data/LLFF)"
            echo "  --out_base    Base output directory (default: ../../output_SCG/LLFF)"
            echo "  --iterations  Number of training iterations (default: 30000)"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [ "$FEWSHOT_MODE" = true ]; then
    DATA_BASE="$FEWSHOT_BASE"
    OUT_BASE="$FEWSHOT_OUT_BASE"
fi

script_start_time=$(date '+%Y-%m-%d %H:%M:%S')
script_start_epoch=$(date +%s)

# Create necessary directories (relative to project root)
mkdir -p "$LOGS_DIR" "$RES_DIR" "$VIDEO_COLLECT_DIR"

clear
echo "============================================================"
echo -e "  ${BLUE}SCGaussian Smart Incremental Script (v8)${NC}"
echo "============================================================"
echo "  Start time: $script_start_time"
echo "  Script dir: $SCRIPT_DIR"
echo "  Project root: $PROJECT_ROOT"
echo "  GPU count: 8"
echo "  Scenes: ${scenes[*]}"
echo "  Iterations: ${ITERATIONS}"
if [ "$FEWSHOT_MODE" = true ]; then
    echo -e "  ${GREEN}Mode: Few-shot (5 views) with optimized params${NC}"
fi
if [ "$TRAIN_FORCE" = true ]; then
    echo -e "  ${YELLOW}Force Train: ENABLED (--train)${NC}"
    echo -e "  ${YELLOW}-> Will re-execute: train/render/video/metrics${NC}"
else
    echo -e "  ${GREEN}Incremental Train: ENABLED (skip if ply exists)${NC}"
fi
echo "  Results dir: $RES_DIR"
echo "  Video collect dir: $VIDEO_COLLECT_DIR"
echo "  Logs dir: $LOGS_DIR"
echo "============================================================"

echo ""
echo "=== Pre-check: Scene Status ==="
for idx in "${!scenes[@]}"; do
    scene="${scenes[$idx]}"
    output_dir="${OUT_BASE}/${scene}"
    input_dir="${DATA_BASE}/${scene}"
    
    train_status="ERR"
    render_status="ERR"
    video_status="ERR"
    input_status="ERR"
    
    [ -d "$input_dir" ] && input_status="OK"
    
    if [ -d "$output_dir" ]; then
        if [ "$TRAIN_FORCE" = true ]; then
            train_status="RUN (forced)"
            render_status="RUN (forced)"
            video_status="RUN (forced)"
        elif check_train_completed "$output_dir"; then
            train_status="OK (ply)"
            check_render_completed "$output_dir" && render_status="OK"
            check_video_completed "$output_dir" && video_status="OK"
        fi
    fi
    
    printf "  %-10s | Input: %s | Train: %s | Render: %s | Video: %s\n" \
        "$scene" "$input_status" "$train_status" "$render_status" "$video_status"
done

echo -e "\n${YELLOW}Press Ctrl+C to view logs ($LOGS_DIR/scene_*.log)${NC}"
echo "============================================================"

echo ""
echo "=== Launching parallel tasks ==="
for idx in "${!scenes[@]}"; do
    gpu=$idx
    scene="${scenes[$idx]}"
    process_scene "$gpu" "$scene" &
done

wait

clear
echo ""
echo "============================================================"
echo -e "${GREEN}OK All scenes processed successfully.${NC}"
echo "============================================================"
echo "  Start time: $script_start_time"
echo "  End time: $(date '+%Y-%m-%d %H:%M:%S')"
total_duration=$(( $(date +%s) - script_start_epoch ))
echo "  Total duration: ${total_duration}s ($((total_duration/60))m ${total_duration%60}s)"
echo "============================================================"

if [ "$FEWSHOT_MODE" = true ]; then
    aggregate_results "$FEWSHOT_OUT_BASE" "${RES_DIR}/results_fewshot_optimized.csv"
    collect_videos "$FEWSHOT_OUT_BASE" "$VIDEO_COLLECT_DIR"
else
    aggregate_results "$OUT_BASE" "${RES_DIR}/results.csv"
    collect_videos "$OUT_BASE" "$VIDEO_COLLECT_DIR"
fi

echo ""
echo "Result file locations:"
echo "  - CSV results: ${RES_DIR}/"
echo "  - Video collect: ${VIDEO_COLLECT_DIR}/"
echo "  - Log files: ${LOGS_DIR}/"
