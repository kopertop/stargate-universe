#!/usr/bin/env python3
"""Fetch GitHub search results with proper JSON handling."""

import subprocess
import json
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def clean_json(raw_text):
    """Remove control characters and try to parse JSON."""
    cleaned = raw_text.replace('\x00', '').replace('\r\n', '\n').replace('\t', '')
    
    # Try parsing the whole thing first
    try:
        data = json.loads(cleaned)
        return data
    except json.JSONDecodeError as e:
        logger.warning(f"JSON parse error at position {e.pos}, trying truncation")
        print(f"Parsed {len(cleaned)} bytes, but got error:\n{cleaned[-500:]}")
        
    # Try to find valid JSON objects in the data stream
    objects = json.JSONDecoder(strict=False).raw_decode(cleaned + ' '] if cleaned.endswith(']') else cleaned)

# GitHub search API call
def github_search(query, sort='updated', order='desc', per_page=30):
    """Perform GitHub Search API query."""
    url = f"https://api.github.com/search/repositories?q={query}&sort={sort}&order={order}&per_page={min(per_page, 100)}"
    
    proc = subprocess.run(
        ['curl', '-s', '--max-time', '30', url],
        capture_output=True, text=True
    )
    
    if proc.returncode != 0:
        logger.error(f"GitHub API request failed: {proc.stderr}")
        return None
    
    data = clean_json(proc.stdout)
    print(f"Parsed {len(data)} characters")
    return data

if __name__ == '__main__':
    # Example query for LLM repositories with stars > 100
    result = github_search(
        q='topic:large-language-model stars:>100',
        sort='updated',
        order='desc'