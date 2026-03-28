#!/bin/bash

# Base paths
DATA_BASE="../data/LLFF"
OUT_BASE="../output_SCG/LLFF"

# All scenes
all_scenes=("fern" "flower" "fortress" "horns" "leaves" "orchids" "room" "trex")

# Split into 4 groups (2 scenes each)
groups=(
  "fern flower"
  "fortress horns"
  "leaves orchids"
  "room trex"
)

# Function to run a group on a specific GPU
run_group() {
  local gpu=$1
  local scenes=($2)  # convert space-separated string to array
  local log_file="group_${gpu}.log"

  echo "Starting group on GPU $gpu with scenes: ${scenes[@]}" | tee -a "$log_file"

  for scene in "${scenes[@]}"; do
    echo "Processing $scene on GPU $gpu" | tee -a "$log_file"

    input_dir="${DATA_BASE}/${scene}"
    output_dir="${OUT_BASE}/${scene}"

    if [ ! -d "$input_dir" ]; then
      echo "Warning: Input directory $input_dir does not exist. Skipping." | tee -a "$log_file"
      continue
    fi

    mkdir -p "$output_dir"

    # Set GPU and run commands
    CUDA_VISIBLE_DEVICES=$gpu python train.py -s "$input_dir" -m "$output_dir" --iterations 30000 -r 8 --eval >> "$log_file" 2>&1
    if [ $? -ne 0 ]; then
      echo "Error during training of $scene on GPU $gpu" | tee -a "$log_file"
      exit 1
    fi

    CUDA_VISIBLE_DEVICES=$gpu python render.py -m "$output_dir" >> "$log_file" 2>&1
    if [ $? -ne 0 ]; then
      echo "Error during rendering of $scene on GPU $gpu" | tee -a "$log_file"
      exit 1
    fi

    CUDA_VISIBLE_DEVICES=$gpu python render_video.py -m "$output_dir" >> "$log_file" 2>&1
    if [ $? -ne 0 ]; then
      echo "Error during video rendering of $scene on GPU $gpu" | tee -a "$log_file"
      exit 1
    fi

    CUDA_VISIBLE_DEVICES=$gpu python metrics.py -m "$output_dir" >> "$log_file" 2>&1
    if [ $? -ne 0 ]; then
      echo "Error during metrics of $scene on GPU $gpu" | tee -a "$log_file"
      exit 1
    fi

    echo "Finished $scene on GPU $gpu" | tee -a "$log_file"
  done

  echo "Group on GPU $gpu completed." | tee -a "$log_file"
}

# Run all groups in parallel
for i in "${!groups[@]}"; do
  run_group "$i" "${groups[$i]}" &
done

# Wait for all background jobs to finish
wait

echo "All groups finished."
