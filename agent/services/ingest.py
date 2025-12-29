import os
from langchain_community.document_loaders import DirectoryLoader
from langchain_text_splitters import RecursiveCharacterTextSplitter
from langchain_ollama import OllamaEmbeddings
from langchain_chroma import Chroma

DOCS_PATH = "/Users/hojinsohn/Echo_RAG/Echo_documents"  # Put your PDF/TXT files here
DB_PATH = "/Users/hojinsohn/Echo_RAG/chroma_db"       # Where the vector DB will be saved

def ingest_documents():
    if not os.path.exists(DOCS_PATH):
        os.makedirs(DOCS_PATH)
        print(f"Created {DOCS_PATH}. Please put your documents there and run again.")
        return

    print("Loading documents...")
    # 'glob="**/*"' loads all files recursively
    loader = DirectoryLoader(DOCS_PATH, glob="**/*", show_progress=True)
    docs = loader.load()

    if not docs:
        print("No documents found.")
        return

    print("Splitting text...")
    text_splitter = RecursiveCharacterTextSplitter(chunk_size=800, chunk_overlap=100)
    splits = text_splitter.split_documents(docs)

    print("Embedding and saving to disk (this may take time)...")
    # Uses Ollama for local embeddings (requires 'ollama pull nomic-embed-text' or similar)
    embeddings = OllamaEmbeddings(model="nomic-embed-text") 
    
    vectorstore = Chroma.from_documents(
        documents=splits,
        embedding=embeddings,
        persist_directory=DB_PATH
    )
    print("Ingestion complete. Database saved to ./chroma_db")

if __name__ == "__main__":
    ingest_documents()