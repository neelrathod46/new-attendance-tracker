import cv2
import numpy as np


def detect_screen_recapture_robust(
    image_path: str, fft_threshold: float = 0.0008, sat_threshold: float = 12.0
) -> dict:
    """Detects screen recaptures of QR codes by combining FFT high-frequency

    energy and HSV chromatic noise analysis.
    """
    img_bgr = cv2.imread(image_path)
    if img_bgr is None:
        raise FileNotFoundError(f"Could not load image from {image_path}")

    # Standardize image size
    h, w = 512, 512
    img_bgr = cv2.resize(img_bgr, (h, w))
    gray = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2GRAY)

    # --- 1. FFT High-Frequency Energy Ratio ---
    f_transform = np.fft.fft2(gray)
    f_shift = np.fft.fftshift(f_transform)
    magnitude = np.abs(f_shift)

    # Mask out the DC center ring (low frequencies) AND cardinal axes (QR alignment lines)
    mask = np.ones((h, w), dtype=np.uint8)
    center_y, center_x = h // 2, w // 2

    # Block DC center
    cv2.circle(mask, (center_x, center_y), 35, 0, -1)

    # Block cardinal axes (+/- 5 pixels around center axes) to ignore QR block edges
    mask[center_y - 5 : center_y + 5, :] = 0
    mask[:, center_x - 5 : center_x + 5] = 0

    # Calculate high-frequency energy ratio outside cardinal axes
    total_energy = np.sum(magnitude)
    high_freq_energy = np.sum(magnitude * mask)
    hf_ratio = high_freq_energy / (total_energy + 1e-6)

    # --- 2. HSV Chromatic Subpixel Fringing ---
    # Screens display subpixel color noise at high-contrast black/white boundaries
    hsv = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2HSV)
    saturation = hsv[:, :, 1]

    # Measure saturation variance specifically along high-contrast edges
    edges = cv2.Canny(gray, 100, 200)
    edge_saturation_mean = np.mean(saturation[edges > 0]) if np.any(edges > 0) else 0

    # Decision logic
    is_fft_screen = hf_ratio > fft_threshold
    is_chromatic_screen = edge_saturation_mean > sat_threshold

    is_screen = is_fft_screen or is_chromatic_screen

    return {
        "is_screen_recapture": is_screen,
        "hf_energy_ratio": float(hf_ratio),
        "edge_saturation_score": float(edge_saturation_mean),
        "flags": {
            "fft_energy_flag": bool(is_fft_screen),
            "chromatic_noise_flag": bool(is_chromatic_screen),
        },
    }


if __name__ == "__main__":
    res = detect_screen_recapture_robust("test_scan.jpg")
    print("--- Robust Screen Recapture Result ---")
    print(f"Screen Detected          : {res['is_screen_recapture']}")
    print(f"High-Freq Energy Ratio   : {res['hf_energy_ratio']:.6f}")
    print(f"Edge Saturation Score    : {res['edge_saturation_score']:.2f}")
    print(f"Triggered Flags          : {res['flags']}")
