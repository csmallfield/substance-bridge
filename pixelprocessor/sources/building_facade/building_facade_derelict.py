"""Building Facade Derelict: the Building Facade with a Disrepair group (broken and boarded windows, cracks,
crumbling render over brick / concrete, rot and mould, moss, ivy, filth). Same layout code; see building_facade.py."""
import os
VARIANT = 'derelict'
exec(compile(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'building_facade.py'), encoding='utf-8').read(),
             __file__, 'exec'))
