import requests
from bs4 import BeautifulSoup
from playwright.sync_api import sync_playwright
import asyncio


url = "https://www.google.com/search?q=holy+forever+chorus+lyrics"

response = requests.get(url, timeout=10)
response.raise_for_status()

soup = BeautifulSoup(response.text, "html.parser")

# Show the title of the webpage
print("Title of the webpage:", soup.title.string)
# Find and print all hyperlinks on the page
for link in soup.find_all('a', href=True):
    print("Hyperlink:", link['href'])

# Find and print all image sources on the page
for img in soup.find_all('img', src=True):
    print("Image source:", img['src'])

# Just print the first 1500 characters of the page content
print("Page content (first 5000 chars):", soup.get_text()[:5000])

# check if it's javaScript rendered

from playwright.async_api import async_playwright

async def fetch_product_data(search_url: str):
    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=True)
        page = await browser.new_page()
        
        # 1. Visit the Search URL determined in Step 1
        await page.goto(search_url)
        
        # 2. Extract the Top 3 Results (Title + Link)
        # (Selectors depend on Google's current DOM, usually .g or similar)
        results = await page.locator('.g').all()
        print(f"Found {len(results)} results")
        
        products = []
        for i in range(3): # Check top 3
            try:
                # Extract text and link
                element = results[i]
                title = await element.locator('h3').first.text_content()
                link = await element.locator('a').first.get_attribute('href')
                
                # 3. DEEP DIVE: Visit the actual product page to get an Image
                # We open a new tab to be safe
                product_page = await browser.new_page()
                await product_page.goto(link)
                
                # Find the "largest" image on the page (heuristic)
                # Or look for OpenGraph tags (meta property="og:image") which are reliable
                image_url = await product_page.locator('meta[property="og:image"]').get_attribute('content')
                
                products.append({
                    "title": title,
                    "url": link,
                    "image": image_url or "placeholder.png"
                })
                
                await product_page.close()
            except:
                continue
                
        await browser.close()
        return products

products = asyncio.run(fetch_product_data(url))
for product in products:
    print(product)