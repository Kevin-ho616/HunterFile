#!/usr/bin/env python3
"""Compatibility entry point; use hunterfiles.py for new integrations."""
from hunterfiles import *

if __name__ == "__main__":
    import sys
    sys.exit(main())
