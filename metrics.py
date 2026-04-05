
from pathlib import Path
import os
from PIL import Image
import torch
import torchvision.transforms.functional as tf
from utils.loss_utils import ssim
from lpipsPyTorch import lpips
import json
from tqdm import tqdm
from utils.image_utils import psnr
from argparse import ArgumentParser
import math

def readImages(renders_dir, gt_dir, mask_dir):
    renders = []
    gts = []
    masks = []
    image_names = []
    for fname in os.listdir(renders_dir):
        render = Image.open(renders_dir / fname)
        gt = Image.open(gt_dir / fname)
        
        if os.path.exists(mask_dir / fname):
            mask = Image.open(mask_dir / fname)
            mask = mask.resize(gt.size)
            mask = tf.to_tensor(mask).unsqueeze(0)[:, :3, :, :].cuda()
        else:
            mask = torch.ones((1, 3, *gt.size[::-1])).float().cuda()
        
        mask_bin = (mask == 1.)
        renders.append(tf.to_tensor(render).unsqueeze(0)[:, :3, :, :].cuda() * mask + (1-mask))
        gts.append(tf.to_tensor(gt).unsqueeze(0)[:, :3, :, :].cuda() * mask + (1-mask))
        masks.append(mask_bin)
        image_names.append(fname)
    return renders, gts, image_names, masks

def evaluate(model_paths):
    full_dict = {}
    per_view_dict = {}
    print(" ")

    for scene_dir in model_paths:
        try:
            print("Scene:", scene_dir)
            full_dict[scene_dir] = {}
            per_view_dict[scene_dir] = {}

            test_dir = Path(scene_dir) / "test"  # ✅ 修复：移除多余空格

            for method in os.listdir(test_dir):
                print("Method:", method)

                full_dict[scene_dir][method] = {}
                per_view_dict[scene_dir][method] = {}

                method_dir = test_dir / method
                gt_dir = method_dir / "gt"  # ✅ 修复：移除多余空格
                renders_dir = method_dir / "renders"  # ✅ 修复
                mask_dir = method_dir / "dtumask"  # ✅ 修复
                
                renders, gts, image_names, masks = readImages(renders_dir, gt_dir, mask_dir)
                
                ssims = []
                psnrs = []
                lpipss = []
                avgs = []

                for idx in tqdm(range(len(renders)), desc="Metric evaluation progress"):  # ✅ 修复
                    o_ssim = ssim(renders[idx], gts[idx])
                    o_psnr = psnr(renders[idx][masks[idx]][None, ...], gts[idx][masks[idx]][None, ...])
                    o_lpips = lpips(renders[idx], gts[idx], net_type='vgg')
                    o_avg = torch.exp(torch.log(torch.tensor([10**(-o_psnr / 10), math.sqrt(1 - o_ssim), o_lpips])).mean())
                    
                    ssims.append(o_ssim)
                    psnrs.append(o_psnr)
                    lpipss.append(o_lpips)
                    avgs.append(o_avg.item())  # ✅ 修复：添加.item()

                print("  SSIM : {:>12.7f}".format(torch.tensor(ssims).mean()))
                print("  PSNR : {:>12.7f}".format(torch.tensor(psnrs).mean()))
                print("  LPIPS: {:>12.7f}".format(torch.tensor(lpipss).mean()))
                print("  AVG: {:>12.7f}".format(torch.tensor(avgs).mean()))
                print(" ")

                # ✅ 修复：AVG 使用 avgs 而非 lpipss
                full_dict[scene_dir][method].update({
                    "SSIM": torch.tensor(ssims).mean().item(),
                    "PSNR": torch.tensor(psnrs).mean().item(),
                    "LPIPS": torch.tensor(lpipss).mean().item(),
                    "AVG": torch.tensor(avgs).mean().item()  # ✅ 关键修复
                })
                
                # ✅ 修复：per_view AVG 使用 avg 而非 lp
                per_view_dict[scene_dir][method].update({
                    "SSIM": {name: ssim for ssim, name in zip(torch.tensor(ssims).tolist(), image_names)},
                    "PSNR": {name: psnr for psnr, name in zip(torch.tensor(psnrs).tolist(), image_names)},
                    "LPIPS": {name: lp for lp, name in zip(torch.tensor(lpipss).tolist(), image_names)},
                    "AVG": {name: avg for avg, name in zip(torch.tensor(avgs).tolist(), image_names)}  # ✅ 修复
                })

            with open(scene_dir + "/results.json", 'w') as fp:
                json.dump(full_dict[scene_dir], fp, indent=True)
            with open(scene_dir + "/per_view.json", 'w') as fp:
                json.dump(per_view_dict[scene_dir], fp, indent=True)
        except Exception as e:
            print("Unable to compute metrics for model", scene_dir)
            print("Error:", str(e))
            import traceback
            traceback.print_exc()

if __name__ == "__main__":  # ✅ 修复：__name__
    device = torch.device("cuda:0")
    torch.cuda.set_device(device)
    
    parser = ArgumentParser(description="Training script parameters")
    parser.add_argument('--model_paths', '-m', required=True, nargs="+", type=str, default=[])
    args = parser.parse_args()
    evaluate(args.model_paths)
