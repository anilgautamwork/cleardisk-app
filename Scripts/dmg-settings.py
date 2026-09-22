from pathlib import Path
root = Path.cwd()
files = [str(root / 'dist/ClearDisk.app')]
symlinks = {'Applications': '/Applications'}
format = 'UDZO'
background = str(root / 'dist/installer-background.tiff')
icon = str(root / 'Scripts/AppIcon.icns')
window_rect = ((240, 180), (520, 640))
icon_locations = {'ClearDisk.app': (260, 180), 'Applications': (260, 412)}
icon_size = 112
text_size = 14
label_pos = 'bottom'
default_view = 'icon-view'
show_toolbar = False
show_status_bar = False
show_sidebar = False
show_pathbar = False
hide_extensions = ['ClearDisk.app']
