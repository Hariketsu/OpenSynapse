from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"
REFERENCE = ASSETS / "OpenSynapse.Icon.Reference.png"
SOURCE = ASSETS / "OpenSynapse.Icon.png"
SIZES = tuple((size, size) for size in (16, 20, 24, 32, 40, 48, 64, 96, 128, 256))


def square_crop(image: Image.Image, box: tuple[int, int, int, int], padding: float) -> Image.Image:
    cropped = image.crop(box)
    alpha_box = cropped.getchannel("A").getbbox()
    if alpha_box is None:
        raise ValueError("Icon crop is fully transparent")
    cropped = cropped.crop(alpha_box)
    side = max(cropped.size)
    canvas_side = int(round(side * (1.0 + 2.0 * padding)))
    canvas = Image.new("RGBA", (canvas_side, canvas_side), (0, 0, 0, 0))
    canvas.alpha_composite(cropped, ((canvas_side - cropped.width) // 2, (canvas_side - cropped.height) // 2))
    return canvas


def extract_reference_logo(reference: Image.Image) -> Image.Image:
    """Remove the generated black canvas without erasing the black snake artwork."""
    width, height = reference.size
    scale_x = width / 1254.0
    scale_y = height / 1254.0
    supersample = 4
    mask = Image.new("L", (width * supersample, height * supersample), 0)
    draw = ImageDraw.Draw(mask)

    def scaled_box(box: tuple[int, int, int, int]) -> tuple[int, int, int, int]:
        left, top, right, bottom = box
        return (
            round(left * scale_x * supersample),
            round(top * scale_y * supersample),
            round(right * scale_x * supersample),
            round(bottom * scale_y * supersample),
        )

    # The supplied mark is a simple battery silhouette. Using a geometric alpha
    # mask preserves its intentionally black outline and three-snake linework.
    draw.rounded_rectangle(
        scaled_box((296, 171, 955, 1191)),
        radius=round(142 * min(scale_x, scale_y) * supersample),
        fill=255,
    )
    draw.rounded_rectangle(
        scaled_box((479, 61, 772, 260)),
        radius=round(66 * min(scale_x, scale_y) * supersample),
        fill=255,
    )
    mask = mask.resize((width, height), Image.Resampling.LANCZOS)
    result = reference.convert("RGBA")
    result.putalpha(mask)
    return result


def save_icon(image: Image.Image, stem: str) -> None:
    master = image.resize((512, 512), Image.Resampling.LANCZOS)
    master.save(ASSETS / f"{stem}.png", optimize=True)
    master.save(ASSETS / f"{stem}.ico", format="ICO", sizes=SIZES)


def build_preview(app: Image.Image, tray: Image.Image) -> None:
    preview = Image.new("RGB", (768, 360), (18, 18, 18))
    draw = ImageDraw.Draw(preview)
    samples = (("APP", app), ("TRAY", tray))
    sizes = (128, 64, 32, 16)
    for row, (label, source) in enumerate(samples):
        top = 24 + row * 168
        draw.text((20, top + 60), label, fill=(68, 214, 44))
        for column, size in enumerate(sizes):
            cell_x = 100 + column * 160
            background = (242, 242, 242) if column % 2 else (35, 35, 35)
            draw.rounded_rectangle((cell_x, top, cell_x + 136, top + 136), radius=12, fill=background)
            rendered = source.resize((size, size), Image.Resampling.LANCZOS)
            preview.paste(rendered, (cell_x + (136 - size) // 2, top + (136 - size) // 2), rendered)
            draw.text((cell_x + 54, top + 142), f"{size}px", fill=(190, 190, 190))
    preview.save(ASSETS / "OpenSynapse.Icon.Preview.png", optimize=True)


def main() -> None:
    if not REFERENCE.exists():
        raise FileNotFoundError(f"Missing supplied logo reference: {REFERENCE}")
    reference = Image.open(REFERENCE).convert("RGB")
    source = extract_reference_logo(reference)
    source.save(SOURCE, optimize=True)
    alpha_box = source.getchannel("A").getbbox()
    if alpha_box is None:
        raise ValueError("Source icon is fully transparent")

    app = square_crop(source, alpha_box, 0.045)
    # The new mark is already a single strong silhouette. A slightly tighter
    # tray crop maximizes legibility at 16-24 px without changing the artwork.
    tray = square_crop(source, alpha_box, 0.015)

    save_icon(app, "OpenSynapse.App")
    save_icon(tray, "OpenSynapse.Tray")
    build_preview(app, tray)
    print(f"Built app and tray icons in {ASSETS}")


if __name__ == "__main__":
    main()
