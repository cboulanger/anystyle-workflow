# AnyStyle workflow

This repo contains a workflow for extracting bibliographic references from PDF
documents using the [AnyStyle extraction engine](https://github.com/inukshuk/anystyle).

# Setup

The workflow also relies on some Python scripts which are called from within ruby using the 
[pycall](https://github.com/mrkn/pycall.rb) gem. For this to work, you need a Python executable 
that has been compiled with the "--enable-shared" option. When installed, install the python 
dependencies with `pip install -r pylib/requirements.txt`

Here is a gist that installs the python and ruby versions used:
https://gist.github.com/cboulanger/f358273bda7ca330aa77d22f656b0750
