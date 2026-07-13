"""
Vercel serverless entry point for MemoryLens AI.
This file re-exports the Flask `app` object so Vercel can serve it.
"""
import sys
import os

# Add the project root to path so our modules are importable
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app import app

# Vercel needs the handler to be named 'app' or accessible at module level
