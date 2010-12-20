'''
sphinx_cython.py

This module monkeypatches sphinx autodoc to support Cython generated
function signatures in the first line of the docstring of functions
implemented as C extensions. 

Copyright (C) Nikolaus Rath <Nikolaus@rath.org>

This file is part of LLFUSE (http://python-llfuse.googlecode.com).
LLFUSE can be distributed under the terms of the GNU LGPL.
'''


import sphinx.ext.autodoc as SphinxAutodoc
from sphinx.util.docstrings import prepare_docstring
import inspect
import re
from sphinx.util import force_decode


TYPE_RE = re.compile(r'(?:int|char)(?:\s+\*?\s*|\s*\*?\s+)([a-zA-Z_].*)')

class MyFunctionDocumenter(SphinxAutodoc.FunctionDocumenter):
    def get_doc(self, encoding=None):
        docstr = self.get_attr(self.object, '__doc__', None)
        
        myname = self.fullname[len(self.modname)+1:]
        if myname.endswith('()'):
            myname = myname[:-2]
            
        if (docstr 
            and docstr.startswith(myname + '(')
            and '\n' in docstr
            and docstr[docstr.index('\n')-1] == ')'):
            docstr = docstr[docstr.index('\n'):]
                    
        if docstr:
            # make sure we have Unicode docstrings, then sanitize and split
            # into lines
            return [prepare_docstring(force_decode(docstr, encoding))]
        return []
        
    def format_args(self):
        myname = self.fullname[len(self.modname)+1:]
        if myname.endswith('()'):
            myname = myname[:-2]
            
        # Try to parse docstring
        docstr = self.get_attr(self.object, '__doc__', None)                    
        if (docstr 
            and docstr.startswith(myname + '(')
            and '\n' in docstr
            and docstr[docstr.index('\n')-1] == ')'):
            args = docstr[len(myname):docstr.index('\n')]
            
            # Get rid of Cython style types declarations
            argl = []
            for arg in [ x.strip() for x in args.split(',') ]:
                hit = TYPE_RE.match(arg)
                if hit:
                    argl.append(hit.group(1))
                else:
                    argl.append(arg)
            args = ', '.join(argl)
            
        else:
            return super(MyFunctionDocumenter, self).format_args() 
            
        # escape backslashes for reST
        args = args.replace('\\', '\\\\')
        return args
            
class MyMethodDocumenter(SphinxAutodoc.MethodDocumenter):
    def get_doc(self, encoding=None):
        docstr = self.get_attr(self.object, '__doc__', None)
        
        myname = self.fullname[len(self.modname)+1:]
        if myname.endswith('()'):
            myname = myname[:-2]
            
        if (docstr 
            and docstr.startswith(myname + '(')
            and '\n' in docstr
            and docstr[docstr.index('\n')-1] == ')'):
            docstr = docstr[docstr.index('\n'):]
                    
        if docstr:
            # make sure we have Unicode docstrings, then sanitize and split
            # into lines
            return [prepare_docstring(force_decode(docstr, encoding))]
        return []
            
    def format_args(self):
        
        myname = self.fullname[len(self.modname)+1:]
        if myname.endswith('()'):
            myname = myname[:-2]
                    
        # Try to parse docstring
        docstr = self.get_attr(self.object, '__doc__', None)
        if (docstr 
            and docstr.startswith(myname + '(')
            and '\n' in docstr
            and docstr[docstr.index('\n')-1] == ')'):
            args = docstr[len(myname)+1:docstr.index('\n')-1]
            
            # Get rid of Cython style types declarations
            argl = []
            for arg in [ x.strip() for x in args.split(',') ]:
                if arg in ('cls', 'self'):
                    continue 
                hit = TYPE_RE.match(arg)
                if hit:
                    argl.append(hit.group(1))
                else:
                    argl.append(arg)
            args = '(%s)' % ', '.join(argl)
            
        else:
            return super(MyMethodDocumenter, self).format_args()  
            
        # escape backslashes for reST
        args = args.replace('\\', '\\\\')
        return args            
            
SphinxAutodoc.MethodDocumenter = MyMethodDocumenter
SphinxAutodoc.FunctionDocumenter = MyFunctionDocumenter