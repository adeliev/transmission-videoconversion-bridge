#!/usr/bin/env python3
"""Exit 0, если в аргументе есть кириллица, иначе exit 1."""
import sys
import re

if len(sys.argv) < 2:
    sys.exit(1)

sys.exit(0 if re.search(r'[а-яА-ЯёЁ]', sys.argv[1]) else 1)
