'''
asyncio.py

Compatibility redirect: asyncio compatibility layer for pyfuse3

Copyright © 2018 Nikolaus Rath <Nikolaus.org>
Copyright © 2018 JustAnotherArchivist

This file is part of pyfuse3. This work may be distributed under
the terms of the GNU LGPL.
'''

from pyfuse3 import asyncio
import sys

sys.modules['pyfuse3_asyncio'] = asyncio
