# -*- coding: utf-8 -*-
'''
sphinx_cython.py

This module removes C style type declarations from function and
method docstrings. It also works around http://trac.cython.org/cython_trac/ticket/812

Copyright © 2010 Nikolaus Rath <Nikolaus.org>

This file is part of pyfuse3. This work may be distributed under
the terms of the GNU LGPL.
'''

import re

TYPE_RE = re.compile(r'(int|char|unicode|str|bytes)(?:\s+\*?\s*|\s*\*?\s+)([a-zA-Z_].*)')

def setup(app):
    app.connect('autodoc-process-signature', process_signature)

def process_signature(app, what, name, obj, options, signature, return_annotation):
    # Some unused arguments
    #pylint: disable=W0613

    if signature is None:
        return (signature, return_annotation)

    new_params = list()
    for param in (x.strip() for x in signature[1:-1].split(',')):
        hit = TYPE_RE.match(param)
        if hit:
            new_params.append(hit.group(2))
        else:
            new_params.append(param)

    return ('(%s)' % ', '.join(new_params), return_annotation)
