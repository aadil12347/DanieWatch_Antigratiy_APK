from PIL import Image
import os

def add_padding(input_path, output_path, target_size=1024, icon_size=400):
    # Open the original logo
    with Image.open(input_path) as logo:
        # Create a new pure black background canvas
        # (Using RGBA for transparency, but we can set background to black)
        # However, for adaptive icons, transparency is better, as the system 
        # applies our specified background color later.
        canvas = Image.new("RGBA", (target_size, target_size), (0, 0, 0, 0))
        
        # Resize original logo to our target relative icon size
        # Maintaining aspect ratio
        logo_aspect = logo.width / logo.height
        if logo_aspect > 1:
            new_w = icon_size
            new_h = int(icon_size / logo_aspect)
        else:
            new_h = icon_size
            new_w = int(icon_size * logo_aspect)
            
        logo_resized = logo.resize((new_w, new_h), Image.Resampling.LANCZOS)
        
        # Calculate centering coordinates
        left = (target_size - new_w) // 2
        top = (target_size - new_h) // 2
        
        # Paste the logo onto the canvas
        canvas.paste(logo_resized, (left, top), mask=logo_resized if logo_resized.mode == 'RGBA' else None)
        
        # Save as PNG
        canvas.save(output_path, "PNG")

if __name__ == "__main__":
    base_dir = r"c:\Users\mdani\Desktop\Daniewatch android app antigravity"
    logo_path = os.path.join(base_dir, "assets", "logo.png")
    output_path = os.path.join(base_dir, "assets", "logo_padded.png")
    
    if os.path.exists(logo_path):
        add_padding(logo_path, output_path)
        print(f"Successfully created padded logo at {output_path}")
    else:
        print(f"Error: Original logo not found at {logo_path}")
