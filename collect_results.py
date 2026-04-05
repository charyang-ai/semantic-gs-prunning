#!/usr/bin/env python3
"""
Collect evaluation metrics from all scenes and export as CSV.
Usage: python collect_results.py [base_dir] [-o output_file]
If base_dir is not given, uses the current working directory.
If output_file is not given, writes to results.csv.
"""

import json
import os
import sys
import csv
import argparse
from pathlib import Path

def extract_metrics(json_path):
    """Extract metrics from a results.json file."""
    try:
        with open(json_path, 'r') as f:
            data = json.load(f)
        # Assume metrics are stored under a key like "ours_30000"
        # You may adjust the key if it varies
        key = "ours_30000"
        if key in data:
            metrics = data[key]
            return {
                'SSIM': metrics.get('SSIM', ''),
                'PSNR': metrics.get('PSNR', ''),
                'LPIPS': metrics.get('LPIPS', ''),
                'AVG': metrics.get('AVG', '')
            }
        else:
            # fallback: take first available key
            first_key = next(iter(data.keys()), None)
            if first_key:
                metrics = data[first_key]
                return {
                    'SSIM': metrics.get('SSIM', ''),
                    'PSNR': metrics.get('PSNR', ''),
                    'LPIPS': metrics.get('LPIPS', ''),
                    'AVG': metrics.get('AVG', '')
                }
            else:
                return None
    except Exception as e:
        print(f"Error reading {json_path}: {e}", file=sys.stderr)
        return None

def main():
    parser = argparse.ArgumentParser(description="Collect metrics from SCGaussian results.")
    parser.add_argument("base_dir", nargs='?', default='.', help="Base directory containing scene subdirectories")
    parser.add_argument("-o", "--output", default="results.csv", help="Output CSV file (default: results.csv)")
    parser.add_argument("--stdout", action="store_true", help="Write to stdout instead of file")
    args = parser.parse_args()

    base_dir = Path(args.base_dir)
    if not base_dir.is_dir():
        print(f"Error: {base_dir} is not a directory.", file=sys.stderr)
        sys.exit(1)

    # Collect results
    results = []
    for scene_dir in base_dir.iterdir():
        if not scene_dir.is_dir():
            continue
        json_file = scene_dir / "results.json"
        if not json_file.exists():
            print(f"Skipping {scene_dir.name}: no results.json", file=sys.stderr)
            continue

        metrics = extract_metrics(json_file)
        if metrics:
            row = {'scene': scene_dir.name, **metrics}
            results.append(row)

    if not results:
        print("No valid results found.", file=sys.stderr)
        sys.exit(1)

    fieldnames = ['scene', 'SSIM', 'PSNR', 'LPIPS', 'AVG']

    if args.stdout:
        writer = csv.DictWriter(sys.stdout, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(results)
    else:
        output_path = Path(args.output)
        # Ensure the parent directory exists
        output_path.parent.mkdir(parents=True, exist_ok=True)
        with open(output_path, 'w', newline='') as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(results)
        print(f"CSV saved to: {output_path.resolve()}")

if __name__ == '__main__':
    main()
