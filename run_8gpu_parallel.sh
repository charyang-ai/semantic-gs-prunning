#!/bin/bash

# Base paths
DATA_BASE="../data/LLFF"
OUT_BASE="../output_SCG/LLFF"

# List of scenes in the order corresponding to GPU indices (0-7)
scenes=("fern" "flower" "fortress" "horns" "leaves" "orchids" "room" "trex")

# Function to process a single scene on a specified GPU
process_scene() {
    local gpu=$1
    local scene=$2
    local log_file="scene_${scene}_gpu${gpu}.log"

    echo "=== Starting scene $scene on GPU $gpu ===" | tee "$log_file"

    input_dir="${DATA_BASE}/${scene}"
    output_dir="${OUT_BASE}/${scene}"

    if [ ! -d "$input_dir" ]; then
        echo "ERROR: Input directory $input_dir does not exist. Skipping." | tee -a "$log_file"
        return 1
    fi

    mkdir -p "$output_dir"

    # 1. Train
    echo "Training $scene on GPU $gpu ..." | tee -a "$log_file"
    CUDA_VISIBLE_DEVICES=$gpu python train.py -s "$input_dir" -m "$output_dir" --iterations 30000 -r 8 --eval >> "$log_file" 2>&1
    if [ $? -ne 0 ]; then
        echo "ERROR: Training failed for $scene on GPU $gpu" | tee -a "$log_file"
        return 1
    fi

    # 2. Render
    echo "Rendering $scene on GPU $gpu ..." | tee -a "$log_file"
    CUDA_VISIBLE_DEVICES=$gpu python render.py -m "$output_dir" >> "$log_file" 2>&1
    if [ $? -ne 0 ]; then
        echo "ERROR: Rendering failed for $scene on GPU $gpu" | tee -a "$log_file"
        return 1
    fi

    # 3. Render video
    echo "Rendering video for $scene on GPU $gpu ..." | tee -a "$log_file"
    CUDA_VISIBLE_DEVICES=$gpu python render_video.py -m "$output_dir" >> "$log_file" 2>&1
    if [ $? -ne 0 ]; then
        echo "ERROR: Video rendering failed for $scene on GPU $gpu" | tee -a "$log_file"
        return 1
    fi

    # 4. Metrics
    echo "Computing metrics for $scene on GPU $gpu ..." | tee -a "$log_file"
    CUDA_VISIBLE_DEVICES=$gpu python metrics.py -m "$output_dir" >> "$log_file" 2>&1
    if [ $? -ne 0 ]; then
        echo "ERROR: Metrics computation failed for $scene on GPU $gpu" | tee -a "$log_file"
        return 1
    fi

    echo "Finished $scene on GPU $gpu successfully." | tee -a "$log_file"
}

# Launch one process per scene, each using a dedicated GPU
for idx in "${!scenes[@]}"; do
    gpu=$idx
    scene="${scenes[$idx]}"
    process_scene "$gpu" "$scene" &
done

# Wait for all background processes to complete
wait

echo "All scenes processed."
