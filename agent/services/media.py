import requests

# Load environment variables
from dotenv import load_dotenv
import os
load_dotenv()

UNSPLASH_ACCESS_KEY = os.getenv("UNSPLASH_ACCESS_KEY")

def fetch_images(query, count=3):
    """
    Fetch image URLs from Unsplash based on a query.
    Returns a list of dicts with url and alt text.
    """
    url = "https://api.unsplash.com/search/photos"
    params = {
        "query": query,
        "per_page": count,
        "client_id": UNSPLASH_ACCESS_KEY
    }

    response = requests.get(url, params=params, timeout=10)
    response.raise_for_status()

    data = response.json()

    images = []
    for item in data["results"]:
        images.append({
            "url": item["urls"]["regular"],
            "alt": item["alt_description"],
            "author": item["user"]["name"]
        })

    return images

# Test the function
if __name__ == "__main__":
    test_query = "Barack Obama"
    images = fetch_images(test_query, count=2)
    for img in images:
        print(f"URL: {img['url']}, Alt: {img['alt']}, Author: {img['author']}")