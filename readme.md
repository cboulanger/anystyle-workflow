# AnyStyle workflow

This repo contains a workflow for extracting bibliographic references from PDF
documents using the [AnyStyle extraction engine](https://github.com/inukshuk/anystyle).

# Setup

todo: ruby 

The workflow also relies on some Python scripts which are called from within ruby using the 
[pycall](https://github.com/mrkn/pycall.rb) gem. For this to work, you need a Python executable 
that has been compiled with the "--enable-shared" option and the

## installing jq
if jq cannot be installed using bundler, try this: 
```
apt get install libjq-dev
RUBYJQ_USE_SYSTEM_LIBRARIES=1 gem install ruby-jq
```

