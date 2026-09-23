from PIL import Image

# 读取原始图标
img = Image.open('Resources/statusbar-icon.png')

# 确保是 RGBA 模式
if img.mode != 'RGBA':
    img = img.convert('RGBA')

# 创建深色版本 (用于浅色主题) - 黑色图标
dark = Image.new('RGBA', img.size, (0, 0, 0, 0))
dark.paste((0, 0, 0, 255), mask=img.split()[3])  # 使用原图的 alpha 作为 mask
dark.save('Resources/statusbar-dark-icon.png')

# 创建浅色版本 (用于深色主题) - 白色图标
light = Image.new('RGBA', img.size, (0, 0, 0, 0))
light.paste((255, 255, 255, 255), mask=img.split()[3])  # 使用原图的 alpha 作为 mask
light.save('Resources/statusbar-light-icon.png')

print("已生成 statusbar-dark-icon.png 和 statusbar-light-icon.png")
