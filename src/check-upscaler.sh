#!/usr/bin/env bash
set -euo pipefail

if command -v realesrgan-ncnn-vulkan >/dev/null 2>&1; then
    echo "UPSCALER_AVAILABLE=true"
    echo "UPSCALER_NAME=Real-ESRGAN"
else
    echo "UPSCALER_AVAILABLE=false"
    echo "UPSCALER_NAME=Real-ESRGAN"
fi
