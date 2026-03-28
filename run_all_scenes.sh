#!/bin/bash

# Base paths
DATA_BASE="../data/LLFF"
OUT_BASE="../output_SCG/LLFF"

# List of scenes (directories under DATA_BASE)
scenes=("fern" "flower" "fortress" "horns" "leaves" "orchids" "room" "trex")

# Iterate over each scene
for scene in "${scenes[@]}"; do
    echo "=========================================="
    echo "Processing scene: $scene"
    echo "=========================================="

    # Define input and output directories
    input_dir="${DATA_BASE}/${scene}"
    output_dir="${OUT_BASE}/${scene}"

    # Check if input scene exists
    if [ ! -d "$input_dir" ]; then
        echo "Warning: Input directory $input_dir does not exist. Skipping."
        continue
    fi

    # Create output directory if it doesn't exist (train will also create)
    mkdir -p "$output_dir"

    # 1. Train
    echo "Starting training for $scene..."
    python train.py -s "$input_dir" -m "$output_dir" --iterations 30000 -r 8 --eval
    if [ $? -ne 0 ]; then
        echo "Error during training of $scene. Exiting."
        exit 1
    fi

    # 2. Render
    echo "Rendering for $scene..."
    python render.py -m "$output_dir"
    if [ $? -ne 0 ]; then
        echo "Error during rendering of $scene. Exiting."
        exit 1
    fi

    # 3. Render video
    echo "Rendering video for $scene..."
    python render_video.py -m "$output_dir"
    if [ $? -ne 0 ]; then
        echo "Error during video rendering of $scene. Exiting."
        exit 1
    fi

    # 4. Metrics
    echo "Computing metrics for $scene..."
    python metrics.py -m "$output_dir"
    if [ $? -ne 0 ]; then
        echo "Error during metrics computation of $scene. Exiting."
        exit 1
    fi

    echo "Finished $scene successfully."
    echo
done

echo "All scenes processed."
