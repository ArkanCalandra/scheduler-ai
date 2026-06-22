from PIL import Image
import os

try:
    img = Image.open('logo.png').convert('RGBA')
    # Resize slightly if it's too big, typical notification icon is 72x72 or 96x96
    img.thumbnail((96, 96), Image.Resampling.LANCZOS)
    data = img.getdata()

    newData = []
    for item in data:
        # If the pixel has any opacity, we convert its color to solid white, keeping original opacity
        if item[3] > 0:
            newData.append((255, 255, 255, item[3]))
        else:
            newData.append((255, 255, 255, 0))

    img.putdata(newData)

    # Save to drawable
    drawable_dir = os.path.join('android', 'app', 'src', 'main', 'res', 'drawable')
    os.makedirs(drawable_dir, exist_ok=True)
    out_path = os.path.join(drawable_dir, 'ic_notification.png')
    img.save(out_path)
    print("Success: saved to", out_path)
except Exception as e:
    print("Error:", str(e))
