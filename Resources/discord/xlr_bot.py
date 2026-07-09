import runpy
from pathlib import Path
runpy.run_path(str(Path(__file__).resolve().parent.parent / 'xlr' / 'xlr_bot.py'))
